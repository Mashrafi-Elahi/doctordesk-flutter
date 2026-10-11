import 'dart:math' as math;

/// Exact Dart port of `geofire-common` used by Firebase Admin SDK.
/// Ensures 100% hash and query bound parity between Node.js ingestion and Flutter queries.
class GeofireUtils {
  static const int geohashPrecision = 10;
  static const String base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const double earthMeriCircumference = 40007860.0;
  static const double metersPerDegreeLatitude = 110574.0;
  static const int bitsPerChar = 5;
  static const int maximumBitsPrecision = 22 * bitsPerChar;
  static const double earthEqRadius = 6378137.0;
  static const double e2 = 0.00669447819799;
  static const double epsilon = 1e-12;

  static double _log2(num x) => math.log(x) / math.ln2;
  static double _degreesToRadians(double degrees) => (degrees * math.pi) / 180.0;

  static double metersToLongitudeDegrees(double distance, double latitude) {
    final radians = _degreesToRadians(latitude);
    final num = math.cos(radians) * earthEqRadius * math.pi / 180.0;
    final denom = 1.0 / math.sqrt(1.0 - e2 * math.sin(radians) * math.sin(radians));
    final deltaDeg = num * denom;
    if (deltaDeg < epsilon) {
      return distance > 0 ? 360.0 : 0.0;
    } else {
      return math.min(360.0, distance / deltaDeg);
    }
  }

  static double longitudeBitsForResolution(double resolution, double latitude) {
    final degs = metersToLongitudeDegrees(resolution, latitude);
    return (degs.abs() > 0.000001) ? math.max(1.0, _log2(360.0 / degs)) : 1.0;
  }

  static double latitudeBitsForResolution(double resolution) {
    return math.min(
      _log2(earthMeriCircumference / 2.0 / resolution),
      maximumBitsPrecision.toDouble(),
    );
  }

  static double wrapLongitude(double longitude) {
    if (longitude <= 180.0 && longitude >= -180.0) {
      return longitude;
    }
    final adjusted = longitude + 180.0;
    if (adjusted > 0) {
      return (adjusted % 360.0) - 180.0;
    } else {
      return 180.0 - (-adjusted % 360.0);
    }
  }

  static int boundingBoxBits(List<double> coordinate, double size) {
    final latDeltaDegrees = size / metersPerDegreeLatitude;
    final latitudeNorth = math.min(90.0, coordinate[0] + latDeltaDegrees);
    final latitudeSouth = math.max(-90.0, coordinate[0] - latDeltaDegrees);
    final bitsLat = (latitudeBitsForResolution(size).floor() * 2);
    final bitsLongNorth = (longitudeBitsForResolution(size, latitudeNorth).floor() * 2 - 1);
    final bitsLongSouth = (longitudeBitsForResolution(size, latitudeSouth).floor() * 2 - 1);
    return math.min(bitsLat, math.min(bitsLongNorth, bitsLongSouth)).toInt().clamp(1, maximumBitsPrecision);
  }

  static List<List<double>> boundingBoxCoordinates(List<double> center, double radius) {
    final latDegrees = radius / metersPerDegreeLatitude;
    final latitudeNorth = math.min(90.0, center[0] + latDegrees);
    final latitudeSouth = math.max(-90.0, center[0] - latDegrees);
    final longDegsNorth = metersToLongitudeDegrees(radius, latitudeNorth);
    final longDegsSouth = metersToLongitudeDegrees(radius, latitudeSouth);
    final longDegs = math.max(longDegsNorth, longDegsSouth);
    return [
      [center[0], center[1]],
      [center[0], wrapLongitude(center[1] - longDegs)],
      [center[0], wrapLongitude(center[1] + longDegs)],
      [latitudeNorth, center[1]],
      [latitudeNorth, wrapLongitude(center[1] - longDegs)],
      [latitudeNorth, wrapLongitude(center[1] + longDegs)],
      [latitudeSouth, center[1]],
      [latitudeSouth, wrapLongitude(center[1] - longDegs)],
      [latitudeSouth, wrapLongitude(center[1] + longDegs)],
    ];
  }

  static String geohashForLocation(List<double> location, [int precision = geohashPrecision]) {
    final latitudeRange = [-90.0, 90.0];
    final longitudeRange = [-180.0, 180.0];
    var hash = '';
    var hashVal = 0;
    var bits = 0;
    var even = true;

    while (hash.length < precision) {
      final val = even ? location[1] : location[0];
      final range = even ? longitudeRange : latitudeRange;
      final mid = (range[0] + range[1]) / 2.0;

      if (val > mid) {
        hashVal = (hashVal << 1) + 1;
        range[0] = mid;
      } else {
        hashVal = (hashVal << 1) + 0;
        range[1] = mid;
      }
      even = !even;

      if (bits < 4) {
        bits++;
      } else {
        bits = 0;
        hash += base32[hashVal];
        hashVal = 0;
      }
    }
    return hash;
  }

  static List<String> geohashQuery(String geohash, int bits) {
    final precision = (bits / bitsPerChar).ceil();
    if (geohash.length < precision) {
      return [geohash, '$geohash~'];
    }
    final truncated = geohash.substring(0, precision);
    final base = truncated.substring(0, truncated.length - 1);
    final lastChar = truncated[truncated.length - 1];
    final lastValue = base32.indexOf(lastChar);
    final significantBits = bits - (base.length * bitsPerChar);
    final unusedBits = bitsPerChar - significantBits;

    final startValue = (lastValue >> unusedBits) << unusedBits;
    final endValue = startValue + (1 << unusedBits);
    if (endValue > 31) {
      return ['$base${base32[startValue]}', '$base~'];
    } else {
      return ['$base${base32[startValue]}', '$base${base32[endValue]}'];
    }
  }

  /// Calculates a set of query bounds to fully contain a given circle, each being a [start, end] pair
  /// where any geohash is guaranteed to be lexicographically >= start and <= end.
  static List<List<String>> geohashQueryBounds(List<double> center, double radiusInMeters) {
    final queryBits = math.max(1, boundingBoxBits(center, radiusInMeters));
    final geohashPrecision = (queryBits / bitsPerChar).ceil();
    final coordinates = boundingBoxCoordinates(center, radiusInMeters);

    final queries = coordinates.map((coord) {
      final hash = geohashForLocation(coord, geohashPrecision);
      return geohashQuery(hash, queryBits);
    }).toList();

    // Deduplicate
    final unique = <List<String>>[];
    for (int i = 0; i < queries.length; i++) {
      final q = queries[i];
      final duplicate = unique.any((u) => u[0] == q[0] && u[1] == q[1]);
      if (!duplicate) {
        unique.add(q);
      }
    }
    return unique;
  }

  static double distanceBetweenKm(List<double> loc1, List<double> loc2) {
    const double radius = 6371.0;
    final latDelta = _degreesToRadians(loc2[0] - loc1[0]);
    final lonDelta = _degreesToRadians(loc2[1] - loc1[1]);
    final a = (math.sin(latDelta / 2.0) * math.sin(latDelta / 2.0)) +
        (math.cos(_degreesToRadians(loc1[0])) *
            math.cos(_degreesToRadians(loc2[0])) *
            math.sin(lonDelta / 2.0) *
            math.sin(lonDelta / 2.0));
    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
    return radius * c;
  }
}
