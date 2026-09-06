import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/services/specialty_matcher.dart';

void main() {
  group('SpecialtyMatcher multilingual tests', () {
    test('matches English complaints', () {
      expect(SpecialtyMatcher.match('I have severe chest pain')?.topSpecialty, 'Cardiologist');
      expect(SpecialtyMatcher.match('fever and chills')?.topSpecialty, 'General Physician');
      expect(SpecialtyMatcher.match('skin rash on arm')?.topSpecialty, 'Dermatologist');
      expect(SpecialtyMatcher.match('bad toothache')?.topSpecialty, 'Dentist');
      expect(SpecialtyMatcher.match('eye problem and blurry vision')?.topSpecialty, 'Ophthalmologist');
      expect(SpecialtyMatcher.match('stomach pain and acidity')?.topSpecialty, 'Gastroenterologist');
      expect(SpecialtyMatcher.match('child health issue')?.topSpecialty, 'Pediatrician');
      expect(SpecialtyMatcher.match('breathing problem')?.topSpecialty, 'Pulmonologist');
      // Bare headache -> General Physician
      expect(SpecialtyMatcher.match('I have headache')?.topSpecialty, 'General Physician');
      // Compound phrase -> Neurologist
      expect(SpecialtyMatcher.match('severe headache with blurred vision')?.topSpecialty, 'Neurologist');
      expect(SpecialtyMatcher.match('chronic migraine')?.topSpecialty, 'Neurologist');
    });

    test('matches Banglish complaints', () {
      expect(SpecialtyMatcher.match('amar buk e batha korche')?.topSpecialty, 'Cardiologist');
      expect(SpecialtyMatcher.match('gae jor ashche')?.topSpecialty, 'General Physician');
      expect(SpecialtyMatcher.match('chamrar shomossha')?.topSpecialty, 'Dermatologist');
      expect(SpecialtyMatcher.match('danter batha')?.topSpecialty, 'Dentist');
      expect(SpecialtyMatcher.match('chokhe shomossha')?.topSpecialty, 'Ophthalmologist');
      expect(SpecialtyMatcher.match('pete batha')?.topSpecialty, 'Gastroenterologist');
      expect(SpecialtyMatcher.match('shas koshto')?.topSpecialty, 'Pulmonologist');
      expect(SpecialtyMatcher.match('komor batha')?.topSpecialty, 'Orthopedist');
    });

    test('matches Bangla script complaints', () {
      expect(SpecialtyMatcher.match('আমার বুকে ব্যথা করছে')?.topSpecialty, 'Cardiologist');
      expect(SpecialtyMatcher.match('গায়ে অনেক জ্বর')?.topSpecialty, 'General Physician');
      expect(SpecialtyMatcher.match('চামড়ার সমস্যা')?.topSpecialty, 'Dermatologist');
      expect(SpecialtyMatcher.match('দাঁতের তীব্র ব্যথা')?.topSpecialty, 'Dentist');
      expect(SpecialtyMatcher.match('চোখের সমস্যা')?.topSpecialty, 'Ophthalmologist');
      expect(SpecialtyMatcher.match('পেটে ব্যথা')?.topSpecialty, 'Gastroenterologist');
      expect(SpecialtyMatcher.match('শ্বাসকষ্ট হচ্ছে')?.topSpecialty, 'Pulmonologist');
      expect(SpecialtyMatcher.match('কোমরে ব্যথা')?.topSpecialty, 'Orthopedist');
    });

    test('returns null for unrecognized or empty input', () {
      expect(SpecialtyMatcher.match(''), isNull);
      expect(SpecialtyMatcher.match('   '), isNull);
      expect(SpecialtyMatcher.match('abcdefghijk qwerty'), isNull);
    });

    test('detects language accurately', () {
      expect(SpecialtyMatcher.detectLanguage('I have fever'), 'en');
      expect(SpecialtyMatcher.detectLanguage('আমার বুকে ব্যথা'), 'bn');
      expect(SpecialtyMatcher.detectLanguage('amar pete batha'), 'banglish');
    });
  });
}
