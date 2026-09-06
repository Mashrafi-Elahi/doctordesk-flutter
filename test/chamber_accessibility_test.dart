import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/widgets/chamber_accessibility.dart';

void main() {
  group('ChamberAccessibility tests', () {
    test('no wheelchair entrance means tier is none regardless of other amenities', () {
      const acc = ChamberAccessibility(
        wheelchairEntrance: false,
        wheelchairParking: true,
        liftAvailable: true,
        accessibleToilet: true,
      );
      expect(acc.tier, AccessibilityTier.none);
    });

    test('wheelchair entrance with only entrance is none', () {
      const acc = ChamberAccessibility(
        wheelchairEntrance: true,
        wheelchairParking: false,
        liftAvailable: false,
        accessibleToilet: false,
      );
      expect(acc.tier, AccessibilityTier.none);
    });

    test('wheelchair entrance with one amenity (lift) is orange', () {
      const acc = ChamberAccessibility(
        wheelchairEntrance: true,
        wheelchairParking: false,
        liftAvailable: true,
        accessibleToilet: false,
      );
      expect(acc.tier, AccessibilityTier.orange);
    });

    test('wheelchair entrance with toilet (weight 2) + lift (weight 1) = 3 (> 2) is yellow', () {
      const acc = ChamberAccessibility(
        wheelchairEntrance: true,
        wheelchairParking: false,
        liftAvailable: true,
        accessibleToilet: true,
      );
      expect(acc.tier, AccessibilityTier.yellow);
    });

    test('wheelchair entrance with all amenities is green', () {
      const acc = ChamberAccessibility(
        wheelchairEntrance: true,
        wheelchairParking: true,
        liftAvailable: true,
        accessibleToilet: true,
      );
      expect(acc.tier, AccessibilityTier.green);
    });
  });
}
