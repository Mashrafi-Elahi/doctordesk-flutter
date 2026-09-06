import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/specialty_matcher.dart';
import '../widgets/specialty_feedback_widget.dart';
import 'doctors_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final Widget? actionWidget;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.actionWidget,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class HealthChatScreen extends StatefulWidget {
  final String? initialMood;

  const HealthChatScreen({super.key, this.initialMood});

  @override
  State<HealthChatScreen> createState() => _HealthChatScreenState();
}

class _HealthChatScreenState extends State<HealthChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _askedFeeling = false;
  bool _answeredFeeling = false;

  String get _todayDateKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMood = prefs.getString('mood_$_todayDateKey');

    setState(() {
      // 1. Initial greeting
      _messages.add(
        ChatMessage(
          text: 'Hello there! 👋 Welcome to DoctorDesk Health Assistant.',
          isUser: false,
        ),
      );

      // 2. Ask feeling ONCE
      _askedFeeling = true;
      if (savedMood != null) {
        _answeredFeeling = true;
        _messages.add(
          ChatMessage(
            text: 'How are you feeling today? You already logged "${_moodLabel(savedMood)}" today. How can I help you right now?',
            isUser: false,
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            text: 'How are you feeling today?',
            isUser: false,
          ),
        );
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _moodLabel(String mood) {
    return switch (mood) {
      'great' => '🌟 Great',
      'good' => '😊 Good',
      'okay' => '😐 Okay',
      'low' => '😔 Low',
      'unwell' => '🤒 Unwell',
      _ => mood,
    };
  }

  void _onSelectMood(String moodKey, String moodText) async {
    setState(() {
      _answeredFeeling = true;
      _messages.add(ChatMessage(text: 'I am feeling $moodText', isUser: true));
    });

    // Save mood
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mood_$_todayDateKey', moodKey);
    ApiService.logFeeling(feeling: moodKey);

    // Rule-based response based on feeling
    Widget? action;
    String replyText = '';

    if (moodKey == 'great' || moodKey == 'good') {
      replyText = 'Glad to hear that! 🟢 Daily health is a blessing. Logged on your Health Calendar.\n\nDescribe any symptoms or search for doctors below if needed.';
    } else if (moodKey == 'okay') {
      replyText = 'Steady and balanced 🟡. Marked on your calendar. Let me know if you need to find any specialist.';
    } else if (moodKey == 'low') {
      replyText = 'Mental health is just as important as physical health 🟣. Speaking with a counselor or psychiatrist can help.';
      action = Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5E35B1)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DoctorsScreen(initialQuery: 'Psychiatrist')),
            );
          },
          icon: const Icon(Icons.psychology, size: 18),
          label: const Text('Find Psychiatrists'),
        ),
      );
    } else if (moodKey == 'unwell') {
      replyText = 'Please take care 🔴. We recommend consulting a General Physician or Medicine doctor.';
      action = Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DoctorsScreen(initialQuery: 'Medicine')),
            );
          },
          icon: const Icon(Icons.medical_services_outlined, size: 18),
          label: const Text('Find General Doctors'),
        ),
      );
    }

    setState(() {
      _messages.add(ChatMessage(text: replyText, isUser: false, actionWidget: action));
    });

    _scrollToBottom();
  }

  void _onSendMessage() {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
    });

    _scrollToBottom();

    final lower = query.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    const greetings = ['hi', 'hello', 'hey', 'salam', 'assalamu alaikum', 'hola', 'hy', 'kemon acho'];
    if (greetings.contains(lower)) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: 'Hello! 👋 How can I help you with your health today?\n\nYou can describe any symptoms you are experiencing (e.g., "fever", "chest pain", "মাথা ব্যথা"), and I will instantly match the right specialist doctor for you.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    // Rule-based matching
    final match = SpecialtyMatcher.match(query);
    if (match != null && match.topSpecialty != null) {
      final spec = match.topSpecialty!;
      final action = Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_services, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recommended: $spec',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DoctorsScreen(initialQuery: spec)),
                  );
                },
                icon: const Icon(Icons.search, size: 16),
                label: Text('Show $spec Specialists'),
              ),
            ),
            const SizedBox(height: 8),
            SpecialtyFeedbackRow(
              inputText: query,
              matchedSpecialty: spec,
              source: 'rule_based',
              onSubmitFeedback: ({
                required String inputText,
                required String matchedSpecialty,
                required String source,
                required bool liked,
              }) => ApiService.submitSpecialtyFeedback(
                inputText: inputText,
                matchedSpecialty: matchedSpecialty,
                source: source,
                liked: liked,
                language: SpecialtyMatcher.detectLanguage(inputText),
              ),
            ),
          ],
        ),
      );

      setState(() {
        _messages.add(
          ChatMessage(
            text: 'Based on your symptoms, it sounds like you should consult a specialist in $spec.',
            isUser: false,
            actionWidget: action,
          ),
        );
      });
    } else {
      final action = Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DoctorsScreen(initialQuery: 'Medicine')),
                  );
                },
                child: const Text('General Doctor'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DoctorsScreen()),
                  );
                },
                child: const Text('All Specialists'),
              ),
            ),
          ],
        ),
      );

      setState(() {
        _messages.add(
          ChatMessage(
            text: 'No exact specialist match found for that description. You can consult a General Physician (GD) or browse our doctor directory.',
            isUser: false,
            actionWidget: action,
          ),
        );
      });
    }

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health Assistant',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Rule-based • Instant matching',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg, colorScheme);
              },
            ),
          ),

          // Quick feeling options if feeling was asked and not answered
          if (_askedFeeling && !_answeredFeeling) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECT YOUR FEELING TODAY:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Text('🌟'),
                        label: const Text('Great'),
                        onPressed: () => _onSelectMood('great', '🌟 Great'),
                      ),
                      ActionChip(
                        avatar: const Text('😊'),
                        label: const Text('Good'),
                        onPressed: () => _onSelectMood('good', '😊 Good'),
                      ),
                      ActionChip(
                        avatar: const Text('😐'),
                        label: const Text('Okay'),
                        onPressed: () => _onSelectMood('okay', '😐 Okay'),
                      ),
                      ActionChip(
                        avatar: const Text('😔'),
                        label: const Text('Low'),
                        onPressed: () => _onSelectMood('low', '😔 Low'),
                      ),
                      ActionChip(
                        avatar: const Text('🤒'),
                        label: const Text('Unwell'),
                        onPressed: () => _onSelectMood('unwell', '🤒 Unwell'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Text input for symptoms / queries
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: 'Describe symptoms (e.g. জ্বর, chest pain)...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                      onSubmitted: (_) => _onSendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _onSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ColorScheme colorScheme) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: msg.isUser ? colorScheme.primary : const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isUser ? Colors.white : Colors.black87,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (msg.actionWidget != null) msg.actionWidget!,
          ],
        ),
      ),
    );
  }
}
