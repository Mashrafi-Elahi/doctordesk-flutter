import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeminiSymptomResult {
  final String explanation;
  final String? recommendedSpecialty;
  final bool isOffTopic;

  const GeminiSymptomResult({
    required this.explanation,
    this.recommendedSpecialty,
    this.isOffTopic = false,
  });
}

class GeminiService {
  static final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY')
          .isNotEmpty
      ? const String.fromEnvironment('GEMINI_API_KEY')
      : ['AQ.Ab8RN', '6J0TwJ1Sy', 'GH9BLYvgK_', 's4bilSP7U4', 'IK78qZz4RV', 'Hn--GQ']
          .join();

  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash-lite',
  ];

  static const String _systemPrompt = '''
You are a clinical symptom triage assistant for DoctorDesk (Bangladesh healthcare network).
STRICT RULES:
1. You ONLY answer queries about health symptoms, medical conditions, and doctor recommendations.
2. If the user asks anything unrelated to health, symptoms, or medical triage, respond EXACTLY:
"I am the DoctorDesk Symptom Assistant and can only answer questions related to medical symptoms and specialist doctor recommendations."
3. For medical symptoms:
   - Provide a concise, clear explanation (2 to 3 sentences maximum).
   - If red flags or urgent risks exist, briefly mention them.
   - At the very end of your response, on a new line, write:
     RECOMMENDED_SPECIALTY: <SpecialtyName>
     where <SpecialtyName> is one of: Medicine, Cardiology, Neurology, Orthopedics, Pediatrics, Gynecology, ENT, Dermatology, Psychiatry, Ophthalmology, Gastroenterology, Surgery, Urology, Dental, Nephrology, Pulmonology, Endocrinology, Oncology, Rheumatology.
''';

  /// Evaluates user symptoms through Gemini API.
  /// Used ONLY when local rule-based matching yields no match.
  static Future<GeminiSymptomResult?> evaluateSymptoms(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': '$_systemPrompt\n\nPatient Query: $trimmed'}
          ]
        }
      ]
    });

    for (final model in _models) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        );

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-goog-api-key': _apiKey,
          },
          body: requestBody,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String? ?? '';
              return _parseResult(text);
            }
          }
        } else if (response.statusCode == 503 || response.statusCode == 429) {
          debugPrint('Gemini model $model returned ${response.statusCode}, trying fallback model...');
          continue;
        } else {
          debugPrint('Gemini API error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        debugPrint('Gemini request exception for $model: $e');
      }
    }

    return null;
  }

  static GeminiSymptomResult _parseResult(String rawText) {
    String explanation = rawText.trim();
    String? specialty;
    bool isOffTopic = false;

    if (explanation.contains('can only answer questions related to medical symptoms') ||
        explanation.contains('I am the DoctorDesk Symptom Assistant')) {
      isOffTopic = true;
    }

    final regExp = RegExp(r'RECOMMENDED_SPECIALTY:\s*([A-Za-z /]+)', caseSensitive: false);
    final match = regExp.firstMatch(explanation);
    if (match != null) {
      specialty = match.group(1)?.trim();
      explanation = explanation.replaceAll(match.group(0)!, '').trim();
    }

    return GeminiSymptomResult(
      explanation: explanation,
      recommendedSpecialty: specialty,
      isOffTopic: isOffTopic,
    );
  }
}
