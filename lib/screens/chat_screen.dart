import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/app_constants.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserUid;
  final bool isDoctor;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserUid,
    this.isDoctor = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final myUid = AuthService.currentUser?.uid;
    final myName = AuthService.currentUser?.displayName ?? (widget.isDoctor ? 'Doctor' : 'Patient');
    if (myUid == null) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await ChatService.sendMessage(
        chatId: widget.chatId,
        senderUid: myUid,
        otherUid: widget.otherUserUid,
        text: text,
        senderName: myName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmCloseChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Consultation?'),
        content: const Text(
          'Closing the consultation will end this follow-up chat session and lock further messaging.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close Consultation'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ChatService.closeChat(widget.chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation closed successfully.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthService.currentUser?.uid;

    return StreamBuilder<ChatSession?>(
      stream: ChatService.streamChatSession(widget.chatId),
      builder: (context, sessionSnap) {
        final session = sessionSnap.data;
        final isClosed = session?.status == 'closed';
        final isExpired = session?.isExpired ?? false;
        final isLimitReached = session?.isLimitReached ?? false;
        final canSend = session == null || session.canSendMessage;
        final remaining = session != null
            ? (session.messageLimit - session.messageCount).clamp(0, session.messageLimit)
            : 20;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                Text(
                  widget.isDoctor ? 'Patient Consultation' : 'Verified Specialist Consultation',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
            actions: [
              if (widget.isDoctor && !isClosed)
                IconButton(
                  icon: const Icon(Icons.lock_clock_outlined, color: Colors.white),
                  tooltip: 'Close Consultation Early',
                  onPressed: _confirmCloseChat,
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Prominent Medical Disclaimer Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.amber.shade50,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Not for emergency medical conditions. In life-threatening emergencies, call 999 or visit the nearest ER immediately.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Consultation Status & Message Limit Banner
                if (isClosed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.red.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.red.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Consultation closed by doctor. Direct messaging is disabled.',
                            style: TextStyle(fontSize: 11.5, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isExpired)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.orange.shade50,
                    child: const Row(
                      children: [
                        Icon(Icons.timer_off_outlined, size: 16, color: Color(0xFF78350F)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Care follow-up window has expired. Direct messaging is disabled.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF78350F), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isLimitReached)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.orange.shade50,
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF78350F)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Message limit reached (${session?.messageLimit}/${session?.messageLimit}). Messaging is locked.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    color: const Color(0xFFF0FDF4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 15, color: Color(0xFF16A34A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active Follow-up • $remaining messages remaining • ${session?.expiresAt != null ? "Closes on ${session!.expiresAt!.toLocal().toString().split(" ")[0]}" : "Active"}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Messages Stream
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: ChatService.streamMessages(widget.chatId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  'Secure Consultation Started',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Send a message describing your symptoms or follow-up questions.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isMe = msg.senderUid == myUid;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.primary : Colors.grey.shade100,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.text,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      color: isMe ? Colors.white : Colors.grey.shade900,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${msg.createdAt.hour.toString().padLeft(2, "0")}:${msg.createdAt.minute.toString().padLeft(2, "0")}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      color: isMe ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Message Input Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          enabled: canSend,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: canSend
                                ? 'Type your message...'
                                : 'Consultation is closed or follow-up expired',
                            hintStyle: GoogleFonts.poppins(fontSize: 13.5, color: Colors.grey.shade400),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            filled: true,
                            fillColor: canSend ? Colors.grey.shade50 : Colors.grey.shade200,
                          ),
                          onSubmitted: (_) => canSend ? _sendMessage() : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: canSend ? AppColors.primary : Colors.grey.shade400,
                        radius: 22,
                        child: IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.send, color: Colors.white, size: 18),
                          onPressed: (_isSending || !canSend) ? null : _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
