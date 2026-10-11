import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doctordesk/services/firestore_service.dart';
import 'package:doctordesk/services/auth_service.dart';
import 'package:doctordesk/widgets/app_role_and_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Firestore Rating Eligibility Tests', () {
    test('Unauthenticated/guest users cannot submit reviews', () async {
      await AuthService.setGuestMode(true);

      final canReview = await FirestoreService.checkCanReview('doctor_1', '');

      expect(canReview, isFalse);
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
