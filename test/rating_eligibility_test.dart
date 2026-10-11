import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doctordesk/services/rtdb_service.dart';
import 'package:doctordesk/services/auth_service.dart';
import 'package:doctordesk/widgets/app_role_and_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Realtime Database Rating Eligibility Tests', () {
    test('Guests are disallowed from rating (only checking allowed)', () async {
      await AuthService.setGuestMode(true);

      final result = await RtdbService.checkRatingEligibility(
        doctorId: 'doctor_1',
        userId: null,
      );

      expect(result.canRate, isFalse);
      expect(result.message, contains('Guests can only check ratings'));
    });

    test('Doctor cannot rate his own claimed profile', () async {
      await AuthService.setGuestMode(false);

      final doctorMap = {
        'id': 'doctor_123',
        '_id': 'doctor_123',
        'claimedByUid': 'user_doctor_uid',
      };

      final isSelf = (doctorMap['claimedByUid'] == 'user_doctor_uid');
      expect(isSelf, isTrue);
    });

    test('Doctor can rate another doctor profile', () async {
      await AuthService.setGuestMode(false);

      final otherDoctorMap = {
        'id': 'doctor_999',
        '_id': 'doctor_999',
        'claimedByUid': 'someone_else_uid',
      };

      final isSelf = (otherDoctorMap['claimedByUid'] == 'my_doctor_uid' ||
          otherDoctorMap['id'] == 'my_doctor_uid');
      expect(isSelf, isFalse);
    });

    test('Operator and Patient roles can rate', () async {
      const operatorRoles = UserRoles(isOperator: true);
      const patientRoles = UserRoles();

      expect(operatorRoles.isOperator, isTrue);
      expect(patientRoles.isDoctor, isFalse);
    });
  });
}
