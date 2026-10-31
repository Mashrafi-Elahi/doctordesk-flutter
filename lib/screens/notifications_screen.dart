// notifications_screen.dart
//
// In-app notifications screen showing appointment confirmations, comments on
// posts, doctor reviews, and system alerts.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';
import '../theme/app_constants.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String _userId = NotificationService.currentUserId;

  IconData _iconForType(String type) => switch (type) {
        'comment' => Icons.chat_bubble_outline_rounded,
        'appointment' => Icons.calendar_today_rounded,
        'review' => Icons.star_outline_rounded,
        _ => Icons.notifications_outlined,
      };

  Color _colorForType(String type) => switch (type) {
        'comment' => const Color(0xFF0288D1),
        'appointment' => AppColors.primary,
        'review' => AppColors.star,
        _ => Colors.blueGrey,
      };

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationService.clearAll(_userId);
              if (mounted) setState(() {});
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationService.notificationsStream(_userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_off_outlined,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Notifications Yet',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You will see notifications when you book appointments, receive replies to your comments, or get clinic updates.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return Container(
                decoration: BoxDecoration(
                  color: n.isRead ? AppColors.surface : AppColors.primaryTint.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                  border: Border.all(
                    color: n.isRead ? AppColors.borderSubtle : AppColors.primary.withValues(alpha: 0.2),
                  ),
                  boxShadow: AppConstants.softShadow,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: _colorForType(n.type).withValues(alpha: 0.15),
                    child: Icon(
                      _iconForType(n.type),
                      color: _colorForType(n.type),
                      size: 20,
                    ),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: GoogleFonts.poppins(
                            fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(n.timestamp),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      n.body,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  trailing: !n.isRead
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                  onTap: () {
                    NotificationService.markAsRead(n.id, _userId);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
