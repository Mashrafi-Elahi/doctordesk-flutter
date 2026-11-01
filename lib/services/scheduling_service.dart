import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'chamber_resolver.dart';
import 'notification_service.dart';

class ParsedSchedule {
  final TimeOfDay start;
  final TimeOfDay end;
  final List<int> visitingDays; // 1 = Mon ... 7 = Sun (matches DateTime.weekday)

  const ParsedSchedule({
    required this.start,
    required this.end,
    this.visitingDays = const [1, 2, 3, 4, 6, 7], // Default Sat–Thu in BD
  });

  bool isVisitingDay(DateTime date) {
    if (visitingDays.isEmpty) return true;
    return visitingDays.contains(date.weekday);
  }
}

class FreeSlotsResult {
  final List<DateTime> slots;
  final String? emptyReason; // 'Fully booked', 'Closed', 'Not a visiting day', 'Visiting hours not set'
  final List<DateTime> nextVisitingDates;
  final int totalCapacity;
  final int confirmedCount;
  final Map<String, dynamic>? overrideData;

  const FreeSlotsResult({
    required this.slots,
    this.emptyReason,
    this.nextVisitingDates = const [],
    this.totalCapacity = 0,
    this.confirmedCount = 0,
    this.overrideData,
  });

  bool get hasSlots => slots.isNotEmpty;
  int get slotsLeft => (totalCapacity - confirmedCount).clamp(0, totalCapacity);
}

class SchedulingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String dateKey(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  }

  static String timeKey(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
  }

  static String slotId(String doctorId, DateTime dt) {
    return '${doctorId}_${dateKey(dt)}_${timeKey(dt)}';
  }

  static int capacity(TimeOfDay start, TimeOfDay end, int slotMinutes) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes || slotMinutes <= 0) return 0;
    return (endMinutes - startMinutes) ~/ slotMinutes;
  }

  static List<DateTime> generateSlots(
    DateTime date,
    TimeOfDay start,
    TimeOfDay end,
    int slotMinutes,
  ) {
    final s = DateTime(date.year, date.month, date.day, start.hour, start.minute);
    final e = DateTime(date.year, date.month, date.day, end.hour, end.minute);
    final diff = e.difference(s).inMinutes;
    if (diff <= 0 || slotMinutes <= 0) return [];
    final n = diff ~/ slotMinutes;
    return List.generate(n, (i) => s.add(Duration(minutes: i * slotMinutes)));
  }

  static ParsedSchedule? parseVisitingHours(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final clean = text.trim();

    // Check for days: e.g. (Sat-Thu), (Sat–Wed), (Fri Closed), etc.
    final lower = clean.toLowerCase();
    List<int> days = [1, 2, 3, 4, 6, 7]; // Default Sat–Thu

    if (lower.contains('sat') && lower.contains('thu')) {
      days = [DateTime.saturday, DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday];
    } else if (lower.contains('sat') && lower.contains('wed')) {
      days = [DateTime.saturday, DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday];
    } else if (lower.contains('everyday') || lower.contains('daily') || lower.contains('all days')) {
      days = [1, 2, 3, 4, 5, 6, 7];
    }

    // Match times: e.g. "5:00 PM – 9:00 PM", "05:00 PM - 09:00 PM", "17:00 - 21:00"
    final regex = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:–|-|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
      caseSensitive: false,
    );
    final match = regex.firstMatch(clean);
    if (match != null) {
      int startH = int.parse(match.group(1)!);
      int startM = match.group(2) != null ? int.parse(match.group(2)!) : 0;
      final startPeriod = match.group(3)?.toLowerCase();

      int endH = int.parse(match.group(4)!);
      int endM = match.group(5) != null ? int.parse(match.group(5)!) : 0;
      final endPeriod = match.group(6)?.toLowerCase();

      if (startPeriod == 'pm' && startH < 12) startH += 12;
      if (startPeriod == 'am' && startH == 12) startH = 0;
      if (endPeriod == 'pm' && endH < 12) endH += 12;
      if (endPeriod == 'am' && endH == 12) endH = 0;

      // Handle cases where start period was omitted but end is PM (e.g. 5:00 - 9:00 PM)
      if (startPeriod == null && endPeriod == 'pm') {
        if (startH < 12 && startH >= 1 && endH >= 12) {
          startH += 12;
        }
      }

      return ParsedSchedule(
        start: TimeOfDay(hour: startH, minute: startM),
        end: TimeOfDay(hour: endH, minute: endM),
        visitingDays: days,
      );
    }

    return null;
  }

  static Future<Map<String, dynamic>?> getDayOverride(String chamberId, DateTime date) async {
    try {
      final docId = '${chamberId}_${dateKey(date)}';
      final snap = await _db.collection('chamber_day_overrides').doc(docId).get();
      if (snap.exists) return snap.data();
    } catch (_) {}
    return null;
  }

  static Future<FreeSlotsResult> getFreeSlots({
    required String chamberId,
    required String doctorId,
    required DateTime date,
    int? defaultSlotMinutes,
  }) async {
    final chamber = await ChamberResolver.resolveChamberRecord(
      chamberId: chamberId,
      doctorId: doctorId,
    );

    final hoursString = chamber?.visitingHours;
    final schedule = parseVisitingHours(hoursString);

    final overrideData = await getDayOverride(chamberId, date);
    final overrideStatus = (overrideData?['status'] ?? '').toString().toLowerCase();

    if (overrideStatus == 'closed') {
      return FreeSlotsResult(
        slots: const [],
        emptyReason: 'Closed',
        overrideData: overrideData,
      );
    }

    if (schedule == null && overrideData == null) {
      return const FreeSlotsResult(
        slots: [],
        emptyReason: 'Visiting hours not set',
      );
    }

    // Check visiting day if no override explicitly opened it
    final isVisiting = schedule?.isVisitingDay(date) ?? true;
    if (!isVisiting && overrideStatus != 'open') {
      final nextDates = getNextVisitingDates(
        schedule: schedule,
        startDate: date,
      );
      return FreeSlotsResult(
        slots: const [],
        emptyReason: 'Not a visiting day',
        nextVisitingDates: nextDates,
      );
    }

    // Determine effective window
    TimeOfDay start = schedule?.start ?? const TimeOfDay(hour: 17, minute: 0);
    TimeOfDay end = schedule?.end ?? const TimeOfDay(hour: 21, minute: 0);
    int slotMinutes = defaultSlotMinutes ?? chamber?.slotMinutes ?? 10;

    if (overrideData != null) {
      if (overrideData['startHour'] != null && overrideData['startMinute'] != null) {
        start = TimeOfDay(
          hour: (overrideData['startHour'] as num).toInt(),
          minute: (overrideData['startMinute'] as num).toInt(),
        );
      }
      if (overrideData['endHour'] != null && overrideData['endMinute'] != null) {
        end = TimeOfDay(
          hour: (overrideData['endHour'] as num).toInt(),
          minute: (overrideData['endMinute'] as num).toInt(),
        );
      }
      if (overrideData['slotMinutes'] != null) {
        slotMinutes = (overrideData['slotMinutes'] as num).toInt().clamp(5, 15);
      }
    }

    final totalCap = capacity(start, end, slotMinutes);
    if (overrideStatus == 'full') {
      return FreeSlotsResult(
        slots: const [],
        emptyReason: 'Fully booked',
        totalCapacity: totalCap,
        confirmedCount: totalCap,
        overrideData: overrideData,
      );
    }

    final allSlots = generateSlots(date, start, end, slotMinutes);
    final dKey = dateKey(date);

    // Retrieve reserved doctor slots across ALL chambers for this doctor on date
    final reservedDocSlots = await _db
        .collection('doctor_slots')
        .where('doctorId', isEqualTo: doctorId)
        .where('date', isEqualTo: dKey)
        .get();

    final takenTimeKeys = <String>{};
    for (final doc in reservedDocSlots.docs) {
      final t = doc.data()['startTime'];
      if (t is Timestamp) {
        takenTimeKeys.add(timeKey(t.toDate()));
      }
    }

    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    final free = allSlots.where((slot) {
      if (takenTimeKeys.contains(timeKey(slot))) return false;
      if (isToday && slot.isBefore(now)) return false;
      return true;
    }).toList();

    final confirmedCount = takenTimeKeys.length;
    final emptyReason = free.isEmpty
        ? (confirmedCount >= totalCap ? 'Fully booked' : 'No available slots today')
        : null;

    return FreeSlotsResult(
      slots: free,
      emptyReason: emptyReason,
      totalCapacity: totalCap,
      confirmedCount: confirmedCount,
      overrideData: overrideData,
    );
  }

  static List<DateTime> getNextVisitingDates({
    ParsedSchedule? schedule,
    required DateTime startDate,
    int count = 3,
  }) {
    final results = <DateTime>[];
    DateTime curr = startDate.add(const Duration(days: 1));
    while (results.length < count && results.length < 14) {
      if (schedule == null || schedule.isVisitingDay(curr)) {
        results.add(DateTime(curr.year, curr.month, curr.day));
      }
      curr = curr.add(const Duration(days: 1));
    }
    return results;
  }

  static Future<void> acceptAppointment({
    required String appointmentId,
    required DateTime slot,
    required String actorUid,
  }) async {
    final apptRef = _db.collection('appointments').doc(appointmentId);
    final targetDateKey = dateKey(slot);

    String resolvedPatientUid = '';
    String resolvedDoctorName = 'Doctor';
    String resolvedChamberName = 'Chamber';
    int assignedQueue = 1;

    await _db.runTransaction((tx) async {
      final apptSnap = await tx.get(apptRef);
      if (!apptSnap.exists) throw StateError('Appointment not found.');
      final appt = apptSnap.data()!;

      final doctorId = (appt['doctorId'] ?? '').toString();
      final chamberId = (appt['chamberId'] ?? 'chamber').toString();
      resolvedPatientUid = (appt['userId'] ?? '').toString();
      resolvedDoctorName = (appt['doctorName'] ?? 'Doctor').toString();

      final targetSlotDocId = slotId(doctorId, slot);
      final slotRef = _db.collection('doctor_slots').doc(targetSlotDocId);
      final counterRef = _db.collection('queues').doc('${chamberId}_$targetDateKey');
      final overrideRef = _db.collection('chamber_day_overrides').doc('${chamberId}_$targetDateKey');

      final slotSnap = await tx.get(slotRef);
      final counter = await tx.get(counterRef);
      final override = await tx.get(overrideRef);

      if (override.exists) {
        final st = (override.data()?['status'] ?? '').toString().toLowerCase();
        if (st == 'closed' || st == 'full') {
          throw StateError('This date is closed or fully booked.');
        }
      }

      if (slotSnap.exists && slotSnap.data()?['appointmentId'] != appointmentId) {
        throw StateError('That slot is already taken by another appointment.');
      }

      final lastPos = (counter.exists ? (counter.data()?['lastQueuePosition'] as num? ?? 0).toInt() : 0);
      assignedQueue = (appt['queuePosition'] as num?)?.toInt() ?? (lastPos + 1);

      // Release previous slot when rescheduling or switching slots
      final oldSlot = appt['slotId']?.toString();
      if (oldSlot != null && oldSlot.isNotEmpty && oldSlot != targetSlotDocId) {
        tx.delete(_db.collection('doctor_slots').doc(oldSlot));
      }

      tx.set(slotRef, {
        'doctorId': doctorId,
        'chamberId': chamberId,
        'appointmentId': appointmentId,
        'date': targetDateKey,
        'startTime': Timestamp.fromDate(slot),
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.update(apptRef, {
        'status': 'confirmed',
        'scheduledTime': Timestamp.fromDate(slot),
        'queuePosition': assignedQueue,
        'slotId': targetSlotDocId,
        'updatedBy': actorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(counterRef, {
        'chamberId': chamberId,
        'date': targetDateKey,
        'lastQueuePosition': appt['queuePosition'] == null ? assignedQueue : lastPos,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    resolvedChamberName = await ChamberResolver.resolveChamberName(
      chamberId: null,
      storedName: null,
      doctorId: null,
    );

    if (resolvedPatientUid.isNotEmpty) {
      try {
        final timeStr = '${slot.hour > 12 ? slot.hour - 12 : (slot.hour == 0 ? 12 : slot.hour)}:${slot.minute.toString().padLeft(2, '0')} ${slot.hour >= 12 ? 'PM' : 'AM'}';
        final dateStr = '${slot.day}/${slot.month}/${slot.year}';
        await NotificationService.createNotification(
          userId: resolvedPatientUid,
          title: 'Appointment Confirmed! 🎉',
          body: 'Confirmed $dateStr at $timeStr, queue #$assignedQueue, $resolvedDoctorName, $resolvedChamberName',
          type: 'appointment_confirmed',
          relatedId: appointmentId,
        );
      } catch (_) {}
    }
  }

  static Future<void> rescheduleAppointment({
    required String appointmentId,
    required DateTime newSlot,
    required String actorUid,
  }) async {
    final apptRef = _db.collection('appointments').doc(appointmentId);
    final targetDateKey = dateKey(newSlot);

    String resolvedPatientUid = '';
    String resolvedDoctorName = 'Doctor';
    DateTime? oldTime;

    await _db.runTransaction((tx) async {
      final apptSnap = await tx.get(apptRef);
      if (!apptSnap.exists) throw StateError('Appointment not found.');
      final appt = apptSnap.data()!;

      final doctorId = (appt['doctorId'] ?? '').toString();
      final chamberId = (appt['chamberId'] ?? 'chamber').toString();
      resolvedPatientUid = (appt['userId'] ?? '').toString();
      resolvedDoctorName = (appt['doctorName'] ?? 'Doctor').toString();

      final oldTs = appt['scheduledTime'];
      if (oldTs is Timestamp) oldTime = oldTs.toDate();

      final targetSlotDocId = slotId(doctorId, newSlot);
      final slotRef = _db.collection('doctor_slots').doc(targetSlotDocId);
      final overrideRef = _db.collection('chamber_day_overrides').doc('${chamberId}_$targetDateKey');

      final slotSnap = await tx.get(slotRef);
      final override = await tx.get(overrideRef);

      if (override.exists) {
        final st = (override.data()?['status'] ?? '').toString().toLowerCase();
        if (st == 'closed' || st == 'full') {
          throw StateError('This date is closed or fully booked.');
        }
      }

      if (slotSnap.exists && slotSnap.data()?['appointmentId'] != appointmentId) {
        throw StateError('That slot is already taken by another appointment.');
      }

      final oldSlot = appt['slotId']?.toString();
      if (oldSlot != null && oldSlot.isNotEmpty && oldSlot != targetSlotDocId) {
        tx.delete(_db.collection('doctor_slots').doc(oldSlot));
      }

      tx.set(slotRef, {
        'doctorId': doctorId,
        'chamberId': chamberId,
        'appointmentId': appointmentId,
        'date': targetDateKey,
        'startTime': Timestamp.fromDate(newSlot),
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.update(apptRef, {
        'status': 'confirmed',
        'scheduledTime': Timestamp.fromDate(newSlot),
        'slotId': targetSlotDocId,
        'updatedBy': actorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (resolvedPatientUid.isNotEmpty) {
      try {
        String formatT(DateTime dt) =>
            '${dt.day}/${dt.month} ${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
        final oldStr = oldTime != null ? formatT(oldTime!) : 'previous time';
        final newStr = formatT(newSlot);

        await NotificationService.createNotification(
          userId: resolvedPatientUid,
          title: 'Appointment Rescheduled 🕒',
          body: 'Rescheduled from $oldStr to $newStr with $resolvedDoctorName.',
          type: 'appointment_rescheduled',
          relatedId: appointmentId,
        );
      } catch (_) {}
    }
  }

  static Future<void> releaseSlotAndLock(String appointmentId) async {
    try {
      final apptRef = _db.collection('appointments').doc(appointmentId);
      final apptSnap = await apptRef.get();
      if (!apptSnap.exists) return;
      final data = apptSnap.data() ?? {};

      // 1. Release doctor slot
      final slotId = data['slotId']?.toString();
      if (slotId != null && slotId.isNotEmpty) {
        try {
          await _db.collection('doctor_slots').doc(slotId).delete();
        } catch (_) {}
      }

      // 2. Release active booking lock
      final activeKey = data['activeBookingKey']?.toString();
      if (activeKey != null && activeKey.isNotEmpty) {
        try {
          await _db.collection('active_bookings').doc(activeKey).delete();
        } catch (_) {}
      } else {
        final patientUid = (data['userId'] ?? '').toString();
        final doctorId = (data['doctorId'] ?? '').toString();
        final chamberId = (data['chamberId'] ?? '').toString();
        final ts = data['scheduledTime'];
        if (patientUid.isNotEmpty && doctorId.isNotEmpty && ts is Timestamp) {
          final dt = ts.toDate();
          final dKey = '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';
          final fallbackKey = '${patientUid}_${doctorId}_${chamberId}_$dKey';
          try {
            await _db.collection('active_bookings').doc(fallbackKey).delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> setDayOverride({
    required String chamberId,
    required String doctorId,
    required DateTime date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    int? slotMinutes,
    String? status,
    String? note,
    required String actorUid,
  }) async {
    final dKey = dateKey(date);
    final docId = '${chamberId}_$dKey';
    final ref = _db.collection('chamber_day_overrides').doc(docId);

    final data = <String, dynamic>{
      'chamberId': chamberId,
      'doctorId': doctorId,
      'date': dKey,
      'updatedBy': actorUid,
      'updatedAt': FieldValue.serverTimestamp(),
      if (startTime != null) 'startHour': startTime.hour,
      if (startTime != null) 'startMinute': startTime.minute,
      if (endTime != null) 'endHour': endTime.hour,
      if (endTime != null) 'endMinute': endTime.minute,
      if (slotMinutes != null) 'slotMinutes': slotMinutes,
      if (status != null) 'status': status,
      if (note != null) 'note': note,
    };

    await ref.set(data, SetOptions(merge: true));
  }

  static Future<List<DocumentSnapshot<Map<String, dynamic>>>> getAffectedAppointments({
    required String chamberId,
    required DateTime date,
    required TimeOfDay newStartTime,
  }) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final threshold = DateTime(date.year, date.month, date.day, newStartTime.hour, newStartTime.minute);

    final snap = await _db
        .collection('appointments')
        .where('chamberId', isEqualTo: chamberId)
        .where('status', isEqualTo: 'confirmed')
        .where('scheduledTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    return snap.docs.where((doc) {
      final ts = doc.data()['scheduledTime'];
      if (ts is Timestamp) {
        return ts.toDate().isBefore(threshold);
      }
      return false;
    }).toList();
  }
}
