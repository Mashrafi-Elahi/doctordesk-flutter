import 'package:flutter/material.dart';
import '../widgets/profile_avatar_button.dart';
import '../services/auth_service.dart';
import 'create_post_screen.dart';

/// Blended Health Feed Screen
/// Combines Health Videos, Doctor Articles, and Community Q&A into a single unified
/// social feed stream (like Facebook/LinkedIn cards) without full-screen video doomscrolling.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // Slots for future YouTube API integration:
  static const String? youtubeApiKey = null;
  static const String? youtubePlaylistId = null;

  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDoctor = AuthService.userRoles.isDoctor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Health Feed',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          ProfileAvatarButton(),
        ],
      ),
      floatingActionButton: isDoctor
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('New Post'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 600));
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // Doctor Post Composer Bar (Facebook-style inline entry on Feed)
            if (isDoctor) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Card(
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(Icons.edit_note, size: 18, color: colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Share a clinical advisory or health tip...',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                              );
                            },
                            child: const Text('Post'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],

            // Top Feed Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Videos'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Articles'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Community Q&A'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Blended Feed Post 1: Video Post Card
            if (_selectedFilter == 'All' || _selectedFilter == 'Videos') ...[
              _buildFeedCard(
                context,
                colorScheme,
                avatarIcon: Icons.ondemand_video,
                avatarColor: Colors.redAccent,
                authorName: 'DoctorDesk Health Media',
                badgeText: 'Verified',
                timeAgo: '2h ago',
                caption:
                    'Watch verified health tips and preventative guidance curated from certified Bangladeshi physicians.',
                attachment: _buildVideoAttachment(colorScheme),
              ),
              const SizedBox(height: 12),
            ],

            // Blended Feed Post 2: Article Post Card
            if (_selectedFilter == 'All' || _selectedFilter == 'Articles') ...[
              _buildFeedCard(
                context,
                colorScheme,
                avatarIcon: Icons.medical_services_outlined,
                avatarColor: colorScheme.primary,
                authorName: 'Clinical Editorial Board',
                badgeText: 'Doctor Post',
                timeAgo: 'Yesterday',
                caption:
                    'Specialist clinical advisories and wellness articles written by registered medical doctors will be published directly to this stream.',
                attachment: _buildArticleAttachment(colorScheme),
              ),
              const SizedBox(height: 12),
            ],

            // Blended Feed Post 3: Community Q&A Post Card
            if (_selectedFilter == 'All' || _selectedFilter == 'Community Q&A') ...[
              _buildFeedCard(
                context,
                colorScheme,
                avatarIcon: Icons.forum_outlined,
                avatarColor: Colors.teal,
                authorName: 'Patient Health Forum',
                badgeText: 'Q&A',
                timeAgo: '2d ago',
                caption:
                    'Have questions about symptoms, medications, or treatment protocols? Ask verified doctors directly.',
                attachment: _buildQnAAttachment(colorScheme),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = label);
        }
      },
    );
  }

  Widget _buildFeedCard(
    BuildContext context,
    ColorScheme colorScheme, {
    required IconData avatarIcon,
    required Color avatarColor,
    required String authorName,
    required String badgeText,
    required String timeAgo,
    required String caption,
    required Widget attachment,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post Header (Author info + time)
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: avatarColor.withValues(alpha: 0.15),
                  child: Icon(avatarIcon, size: 20, color: avatarColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeAgo,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Post Caption
            Text(
              caption,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),

            // Embedded Attachment (Video, Article, or Q&A card)
            attachment,
          ],
        ),
      ),
    );
  }

  Widget _buildVideoAttachment(ColorScheme colorScheme) {
    const isConfigured = youtubeApiKey != null && youtubePlaylistId != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 36,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            isConfigured ? 'Playing video feed...' : 'Video feed coming soon',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Curated Bangladeshi doctor health guides and clinical videos will be linked here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleAttachment(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Clinical Advisories & Articles',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No articles published yet — BMDC-verified doctors can publish medical guidance directly to patients once doctor portal goes live.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildQnAAttachment(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                'Community Medical Inquiries',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No community questions submitted yet — patient inquiries answered by registered specialists will appear here.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}
