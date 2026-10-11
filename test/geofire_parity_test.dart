import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/services/geofire_utils.dart';

void main() {
  test('GeofireUtils exact parity with Node.js geofire-common', () {
    const lat = 23.7391955;
    const lng = 90.3824471;
    const location = [lat, lng];

    // 1. Check geohash
    final hash = GeofireUtils.geohashForLocation(location);
    expect(hash, 'wh0r09w6zd');

    // 2. Check query bounds for 5000m radius
    final bounds = GeofireUtils.geohashQueryBounds(location, 5000.0);
    expect(bounds.length, 4);
    expect(bounds, [
      ['wh0r0', 'wh0r8'],
      ['wh0ph', 'wh0ps'],
      ['wh0q8', 'wh0qh'],
      ['wh0ns', 'wh0n~'],
    ]);

    // 3. Distance test
    final dist = GeofireUtils.distanceBetweenKm([23.7391955, 90.3824471], [23.7766326, 90.3953894]);
    expect(dist > 4.0 && dist < 5.0, true);
  });
}
