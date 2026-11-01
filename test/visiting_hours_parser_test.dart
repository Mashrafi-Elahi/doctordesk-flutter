import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/services/scheduling_service.dart';

void main() {
  group('parseVisitingHours unit tests', () {
    test('parses en-dash with (Sat–Thu)', () {
      final res = SchedulingService.parseVisitingHours('5:00 PM – 9:00 PM (Sat–Thu)');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 17, minute: 0));
      expect(res.end, const TimeOfDay(hour: 21, minute: 0));
      expect(res.visitingDays, [
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]);
    });

    test('parses hyphen with (Sat-Thu)', () {
      final res = SchedulingService.parseVisitingHours('5:00 PM - 9:00 PM (Sat-Thu)');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 17, minute: 0));
      expect(res.end, const TimeOfDay(hour: 21, minute: 0));
      expect(res.visitingDays, [
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]);
    });

    test('parses em-dash with (Sat—Thu)', () {
      final res = SchedulingService.parseVisitingHours('5:00 PM — 9:00 PM (Sat—Thu)');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 17, minute: 0));
      expect(res.end, const TimeOfDay(hour: 21, minute: 0));
      expect(res.visitingDays, [
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]);
    });

    test('parses "to" keyword with (Sat to Thu)', () {
      final res = SchedulingService.parseVisitingHours('5:00 PM to 9:00 PM (Sat to Thu)');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 17, minute: 0));
      expect(res.end, const TimeOfDay(hour: 21, minute: 0));
      expect(res.visitingDays, [
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]);
    });

    test('parses 24h format (17:00 - 21:00)', () {
      final res = SchedulingService.parseVisitingHours('17:00 - 21:00');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 17, minute: 0));
      expect(res.end, const TimeOfDay(hour: 21, minute: 0));
    });

    test('parses morning 12h format (09:00 AM - 01:00 PM)', () {
      final res = SchedulingService.parseVisitingHours('09:00 AM - 01:00 PM');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 9, minute: 0));
      expect(res.end, const TimeOfDay(hour: 13, minute: 0));
    });

    test('parses discrete day list (Sat, Sun, Mon)', () {
      final res = SchedulingService.parseVisitingHours('5:00 PM - 9:00 PM (Sat, Sun, Mon)');
      expect(res, isNotNull);
      expect(res!.visitingDays.toSet(), {
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
      });
    });

    test('parses day range (Sun–Thu)', () {
      final res = SchedulingService.parseVisitingHours('6:00 PM – 10:00 PM (Sun–Thu)');
      expect(res, isNotNull);
      expect(res!.start, const TimeOfDay(hour: 18, minute: 0));
      expect(res.end, const TimeOfDay(hour: 22, minute: 0));
      expect(res.visitingDays, [
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]);
    });

    test('parses everyday / daily keyword', () {
      final res = SchedulingService.parseVisitingHours('4:00 PM - 8:00 PM Everyday');
      expect(res, isNotNull);
      expect(res!.visitingDays.length, 7);
    });

    test('returns null for null, empty or invalid strings', () {
      expect(SchedulingService.parseVisitingHours(null), isNull);
      expect(SchedulingService.parseVisitingHours(''), isNull);
      expect(SchedulingService.parseVisitingHours('No hours available'), isNull);
      expect(SchedulingService.parseVisitingHours('10:00 PM - 8:00 PM'), isNull); // Start after end
    });

    test('capacity calculation handles zero or inverted ranges gracefully', () {
      final cap = SchedulingService.capacity(
        const TimeOfDay(hour: 20, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
        10,
      );
      expect(cap, 0);
    });
  });
}
