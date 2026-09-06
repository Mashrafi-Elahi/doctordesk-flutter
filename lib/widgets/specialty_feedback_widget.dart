// specialty_feedback_widget.dart
// Drop this under any specialty-suggestion card (rule-based OR Gemini result).
// One vote per suggestion shown; disables after tap; never blocks UI on network failure.

import 'package:flutter/material.dart';

class SpecialtyFeedbackRow extends StatefulWidget {
  final String inputText;
  final String matchedSpecialty;
  final String source; // 'rule_based' or 'gemini'
  final Future<void> Function({
    required String inputText,
    required String matchedSpecialty,
    required String source,
    required bool liked,
  }) onSubmitFeedback; // wire this to ApiService.submitSpecialtyFeedback

  const SpecialtyFeedbackRow({
    super.key,
    required this.inputText,
    required this.matchedSpecialty,
    required this.source,
    required this.onSubmitFeedback,
  });

  @override
  State<SpecialtyFeedbackRow> createState() => _SpecialtyFeedbackRowState();
}

class _SpecialtyFeedbackRowState extends State<SpecialtyFeedbackRow> {
  bool? _voted; // null = not voted yet, true = liked, false = disliked

  void _vote(bool liked) {
    if (_voted != null) return; // lock after first tap
    setState(() => _voted = liked);
    try {
      widget
          .onSubmitFeedback(
            inputText: widget.inputText,
            matchedSpecialty: widget.matchedSpecialty,
            source: widget.source,
            liked: liked,
          )
          .catchError((_) {});
    } catch (_) {
      // Fire-and-forget — failures are swallowed, never shown to user
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_voted != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _voted! ? 'Thanks for confirming!' : "Thanks — we'll improve this.",
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Was this suggestion helpful?',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _vote(true),
            child: const Icon(Icons.thumb_up_outlined, size: 16),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _vote(false),
            child: const Icon(Icons.thumb_down_outlined, size: 16),
          ),
        ],
      ),
    );
  }
}
