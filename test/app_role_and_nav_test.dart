import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/widgets/app_role_and_nav.dart';

void main() {
  group('AppBottomNavConfig & UserRoles tests', () {
    test('provides single source of truth for third tab labels', () {
      expect(AppBottomNavConfig.thirdTabLabel(AppRole.patient), 'Appointments');
      expect(AppBottomNavConfig.thirdTabLabel(AppRole.doctor), 'Manage');
      expect(AppBottomNavConfig.thirdTabLabel(AppRole.operator), 'Desk');
    });

    test('hides third tab when chamberCount == 0 for doctor/operator', () {
      const zeroChambers = UserRoles(isDoctor: true, isOperator: true, chamberCount: 0);
      expect(AppBottomNavConfig.showThirdTab(AppRole.doctor, zeroChambers), isFalse);
      expect(AppBottomNavConfig.showThirdTab(AppRole.operator, zeroChambers), isFalse);
      // Patient tab always shows regardless of chambers
      expect(AppBottomNavConfig.showThirdTab(AppRole.patient, zeroChambers), isTrue);

      const withChambers = UserRoles(isDoctor: true, isOperator: true, chamberCount: 2);
      expect(AppBottomNavConfig.showThirdTab(AppRole.doctor, withChambers), isTrue);
      expect(AppBottomNavConfig.showThirdTab(AppRole.operator, withChambers), isTrue);
      expect(AppBottomNavConfig.showThirdTab(AppRole.patient, withChambers), isTrue);
    });

    test('UserRoles computes availableRoles and hasMultipleRoles correctly', () {
      const patientOnly = UserRoles(isDoctor: false, isOperator: false);
      expect(patientOnly.availableRoles, [AppRole.patient]);
      expect(patientOnly.hasMultipleRoles, isFalse);

      const doctorAndOperator = UserRoles(isDoctor: true, isOperator: true, chamberCount: 1);
      expect(doctorAndOperator.availableRoles, [AppRole.patient, AppRole.doctor, AppRole.operator]);
      expect(doctorAndOperator.hasMultipleRoles, isTrue);
    });
  });
}
