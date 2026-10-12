import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/doctor.dart';
import 'app_language.dart';

/// Central singleton service for Text-to-Speech (TTS) and Read Aloud accessibility.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  static const String _prefKey = 'read_aloud_enabled';
  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> isReadAloudEnabled = ValueNotifier<bool>(false);
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isReadAloudEnabled.value = prefs.getBool(_prefKey) ?? false;

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _tts.setErrorHandler((_) {
        _isSpeaking = false;
      });
    } catch (e) {
      debugPrint('TtsService init error: $e');
    }
  }

  Future<void> setReadAloud(bool enabled) async {
    isReadAloudEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}

    if (enabled) {
      await speak(AppLanguage.isBengali ? 'রিড অ্যালাউড চালু হয়েছে' : 'Read aloud enabled');
    } else {
      await stop();
    }
  }

  Future<void> setLocale(String code) async {
    try {
      final lang = code.startsWith('bn') ? 'bn-BD' : 'en-US';
      await _tts.setLanguage(lang);
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      final language = AppLanguage.isBengali ? 'bn-BD' : 'en-US';
      await _tts.setLanguage(language);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TtsService speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
      _isSpeaking = false;
    } catch (_) {}
  }

  /// Speaks doctor summary information (replaces old Doctor Detail screen control)
  Future<void> speakDoctorSummary(Doctor doctor) async {
    final speech = StringBuffer();
    speech.write('${doctor.name}. ');
    if (doctor.designation != null && doctor.designation!.isNotEmpty) {
      speech.write('${doctor.designation}. ');
    }
    if (doctor.isBmdcVerified) {
      speech.write('BMDC Verified Specialist. ');
    }
    if (doctor.specialities.isNotEmpty) {
      speech.write('Specialities: ${doctor.specialities.join(", ")}. ');
    }
    if (doctor.experienceYears > 0) {
      speech.write('${doctor.experienceYears.toInt()} years of experience. ');
    }
    if (doctor.ratingCount > 0) {
      speech.write(
          'Rating: ${doctor.ratingAverage?.toStringAsFixed(1) ?? "-"} stars out of ${doctor.ratingCount} reviews. ');
    } else {
      speech.write('Not rated yet. ');
    }
    if (doctor.chambers.isNotEmpty) {
      speech.write('Chambers: ');
      for (final c in doctor.chambers) {
        if (c.hospitalName != null) speech.write('${c.hospitalName}. ');
        if (c.isAccessible) speech.write('Wheelchair accessible chamber. ');
      }
    }
    await speak(speech.toString());
  }
}
