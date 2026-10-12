import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight app-wide language state. The app has a large amount of custom
/// UI text, so this notifier rebuilds the whole shell when the preference
/// changes; `tr` is used by shared labels and screens as they are migrated.
class AppLanguage {
  static final ValueNotifier<String> code = ValueNotifier<String>('en');

  static bool get isBengali => code.value == 'bn';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    code.value = prefs.getString('setting_language') == 'Bengali' ? 'bn' : 'en';
  }

  static Future<void> setLanguage(String language) async {
    final next = language == 'Bengali' ? 'bn' : 'en';
    code.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'setting_language',
      next == 'bn' ? 'Bengali' : 'English',
    );
  }
}

String tr(String english) {
  if (!AppLanguage.isBengali) return english;
  const translations = <String, String>{
    'Home': 'হোম',
    'Feed': 'ফিড',
    'Appointments': 'অ্যাপয়েন্টমেন্ট',
    'Inbox': 'ইনবক্স',
    'Profile': 'প্রোফাইল',
    'Manage': 'ম্যানেজ',
    'Desk': 'ডেস্ক',
    'Admin': 'অ্যাডমিন',
    'Upcoming': 'আসন্ন',
    'Past Visits': 'পূর্বের ভিজিট',
    'Patient Queue': 'রোগীর কিউ',
    'Chambers': 'চেম্বার',
    'Health Feed & Q&A': 'স্বাস্থ্য ফিড ও প্রশ্নোত্তর',
    'Settings': 'সেটিংস',
    'Language': 'ভাষা',
    'English (US)': 'ইংরেজি (US)',
    'বাংলা (Bengali)': 'বাংলা',
    'Clear Local Health Cache': 'লোকাল স্বাস্থ্য ক্যাশ পরিষ্কার করুন',
    'Patient Profile': 'রোগীর প্রোফাইল',
    'Doctor Profile': 'ডাক্তারের প্রোফাইল',
    'No upcoming appointments': 'কোনো আসন্ন অ্যাপয়েন্টমেন্ট নেই',
    'Sign in to view appointments': 'অ্যাপয়েন্টমেন্ট দেখতে লগ ইন করুন',
    'My Reviews': 'আমার রিভিউ',
    'Saved Doctors': 'সেভ করা ডাক্তার',
    'Medical History & Reports': 'মেডিকেল ইতিহাস ও রিপোর্ট',
    'Book Appointment': 'অ্যাপয়েন্টমেন্ট বুক করুন',
    'See All': 'সব দেখুন',
    'Specialities': 'বিশেষত্ব',
    'Top Doctors': 'শীর্ষ ডাক্তার',
    'Doctors Near Me': 'আমার কাছের ডাক্তার',
  };
  return translations[english] ?? english;
}
