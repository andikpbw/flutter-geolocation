import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Standard display formats for geographic coordinates.
enum GeoCoordinateFormat {
  /// Signed decimal degrees, e.g. `-6.175392, 106.827153`.
  decimalDegrees,

  /// Decimal degrees with cardinal hemisphere indicators,
  /// e.g. `6.175392° S, 106.827153° E`.
  decimalDegreesHemisphere,

  /// Degrees and decimal minutes, e.g. `6° 10.5235' S, 106° 49.6292' E`.
  degreesDecimalMinutes,

  /// Degrees, minutes, and seconds, e.g. `6° 10' 31.41" S, 106° 49' 37.75" E`.
  degreesMinutesSeconds,

  /// Base-32 Geohash string, e.g. `qqguw5e3r`.
  geohash,
}

/// 16-point compass rose cardinal and intercardinal directions.
enum CompassDirection {
  /// North (0°).
  north('N', 'North', 0.0),

  /// North-northeast (22.5°).
  northNortheast('NNE', 'North-Northeast', 22.5),

  /// Northeast (45°).
  northeast('NE', 'Northeast', 45.0),

  /// East-northeast (67.5°).
  eastNortheast('ENE', 'East-Northeast', 67.5),

  /// East (90°).
  east('E', 'East', 90.0),

  /// East-southeast (112.5°).
  eastSoutheast('ESE', 'East-Southeast', 112.5),

  /// Southeast (135°).
  southeast('SE', 'Southeast', 135.0),

  /// South-southeast (157.5°).
  southSoutheast('SSE', 'South-Southeast', 157.5),

  /// South (180°).
  south('S', 'South', 180.0),

  /// South-southwest (202.5°).
  southSouthwest('SSW', 'South-Southwest', 202.5),

  /// Southwest (225°).
  southwest('SW', 'Southwest', 225.0),

  /// West-southwest (247.5°).
  westSouthwest('WSW', 'West-Southwest', 247.5),

  /// West (270°).
  west('W', 'West', 270.0),

  /// West-northwest (292.5°).
  westNorthwest('WNW', 'West-Northwest', 292.5),

  /// Northwest (315°).
  northwest('NW', 'Northwest', 315.0),

  /// North-northwest (337.5°).
  northNorthwest('NNW', 'North-Northwest', 337.5);

  const CompassDirection(this.abbreviation, this.label, this.centerDegrees);

  /// Short compass code such as `N`, `NE`, or `WSW`.
  final String abbreviation;

  /// Full English label such as `North-Northeast`.
  final String label;

  /// Nominal azimuth in degrees clockwise from true north.
  final double centerDegrees;

  /// Converts a bearing in degrees (any real number) to the nearest 16-point
  /// [CompassDirection].
  static CompassDirection fromBearing(double degrees) {
    final normalized = GeoMath.normalizeBearing(degrees);
    final index = ((normalized + 11.25) ~/ 22.5) % 16;
    return CompassDirection.values[index];
  }

  /// Converts a bearing in degrees to the nearest 8-point cardinal or
  /// ordinal [CompassDirection] (`N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`).
  static CompassDirection fromBearing8Point(double degrees) {
    final normalized = GeoMath.normalizeBearing(degrees);
    final index = (((normalized + 22.5) ~/ 45.0) % 8) * 2;
    return CompassDirection.values[index];
  }
}

/// Result of a WGS-84 geodesic inverse computation between two coordinates.
@immutable
class GeodesicResult {
  /// Creates a geodesic computation result.
  const GeodesicResult({
    required this.distanceMeters,
    required this.initialBearingDegrees,
    required this.finalBearingDegrees,
    this.usedEllipsoid = true,
  });

  /// Shortest distance over the Earth's surface in meters.
  final double distanceMeters;

  /// Forward azimuth at the starting point in degrees `[0, 360)`.
  final double initialBearingDegrees;

  /// Forward azimuth at the destination point in degrees `[0, 360)`.
  final double finalBearingDegrees;

  /// Whether WGS-84 Vincenty ellipsoidal math converged (`true`) or fell back
  /// to spherical math for nearly antipodal points (`false`).
  final bool usedEllipsoid;

  /// Distance expressed in kilometers.
  double get distanceKilometers => distanceMeters / 1000.0;

  /// Distance expressed in statute miles.
  double get distanceMiles => distanceMeters / 1609.344;

  /// Distance expressed in nautical miles.
  double get distanceNauticalMiles => distanceMeters / 1852.0;

  /// Initial 16-point compass direction toward the destination.
  CompassDirection get compassDirection =>
      CompassDirection.fromBearing(initialBearingDegrees);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeodesicResult &&
        other.distanceMeters == distanceMeters &&
        other.initialBearingDegrees == initialBearingDegrees &&
        other.finalBearingDegrees == finalBearingDegrees &&
        other.usedEllipsoid == usedEllipsoid;
  }

  @override
  int get hashCode => Object.hash(
    distanceMeters,
    initialBearingDegrees,
    finalBearingDegrees,
    usedEllipsoid,
  );

  @override
  String toString() =>
      'GeodesicResult(distanceMeters: ${distanceMeters.toStringAsFixed(3)}, '
      'initialBearing: ${initialBearingDegrees.toStringAsFixed(2)}°, '
      'finalBearing: ${finalBearingDegrees.toStringAsFixed(2)}°)';
}

/// Low-level WGS-84 geodetic constants and helper utilities.
abstract final class GeoMath {
  /// WGS-84 semi-major axis (equatorial radius) in meters.
  static const double wgs84A = 6378137.0;

  /// WGS-84 flattening factor.
  static const double wgs84F = 1.0 / 298.257223563;

  /// WGS-84 semi-minor axis (polar radius) in meters.
  static const double wgs84B = wgs84A * (1.0 - wgs84F);

  /// IUGG mean spherical Earth radius in meters.
  static const double meanEarthRadiusMeters = 6371008.7714;

  /// Conversion factor from degrees to radians.
  static const double degToRadFactor = math.pi / 180.0;

  /// Conversion factor from radians to degrees.
  static const double radToDegFactor = 180.0 / math.pi;

  /// Converts [degrees] to radians.
  static double toRadians(double degrees) => degrees * degToRadFactor;

  /// Converts [radians] to degrees.
  static double toDegrees(double radians) => radians * radToDegFactor;

  /// Normalizes any angle in degrees into `[0.0, 360.0)`.
  static double normalizeBearing(double degrees) {
    if (!degrees.isFinite) return 0.0;
    final mod = degrees % 360.0;
    return mod < 0 ? mod + 360.0 : (mod == 360.0 ? 0.0 : mod);
  }

  /// Computes the shortest signed angular difference from [fromDegrees] to
  /// [toDegrees] in `(-180.0, 180.0]`.
  static double shortestAngleDelta(double fromDegrees, double toDegrees) {
    final diff = (toDegrees - fromDegrees + 540.0) % 360.0 - 180.0;
    return diff == -180.0 ? 180.0 : diff;
  }

  /// Wraps any longitude value into `[-180.0, 180.0]`.
  static double normalizeLongitude(double longitude) {
    if (!longitude.isFinite) return 0.0;
    if (longitude >= -180.0 && longitude <= 180.0) return longitude;
    final wrapped = ((longitude + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;
    return wrapped == -180.0 && longitude > 0 ? 180.0 : wrapped;
  }

  /// Clamps a latitude value into `[-90.0, 90.0]`.
  static double clampLatitude(double latitude) {
    if (!latitude.isFinite) return 0.0;
    return latitude.clamp(-90.0, 90.0);
  }

  /// Formats a distance in meters into a human-friendly metric string
  /// (e.g. `42 m` or `3.45 km`).
  static String formatDistanceMetric(double meters, {int decimals = 2}) {
    if (!meters.isFinite || meters < 0) return '0 m';
    if (meters < 1000.0) {
      return meters < 10.0
          ? '${meters.toStringAsFixed(1)} m'
          : '${meters.round()} m';
    }
    return '${(meters / 1000.0).toStringAsFixed(decimals)} km';
  }

  /// Formats a distance in meters into a human-friendly imperial string
  /// (e.g. `320 ft` or `1.25 mi`).
  static String formatDistanceImperial(double meters, {int decimals = 2}) {
    if (!meters.isFinite || meters < 0) return '0 ft';
    final feet = meters * 3.280839895;
    if (feet < 528.0) {
      return '${feet.round()} ft';
    }
    return '${(meters / 1609.344).toStringAsFixed(decimals)} mi';
  }
}

/// An immutable WGS-84 geographic coordinate pair ([latitude], [longitude]).
///
/// Provides survey-grade Vincenty ellipsoidal distance/bearing calculations,
/// fast Haversine distance, geodesic interpolation, cross-track error,
/// Geohash encoding/decoding, and multi-format parsing & formatting.
@immutable
class GeoCoordinate {
  /// Creates a validated [GeoCoordinate].
  ///
  /// Throws an [ArgumentError] if [latitude] is outside `[-90, 90]`,
  /// [longitude] is outside `[-180, 180]`, or either value is non-finite.
  GeoCoordinate(this.latitude, this.longitude) {
    if (!latitude.isFinite || latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Latitude must be a finite number between -90.0 and 90.0.',
      );
    }
    if (!longitude.isFinite || longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Longitude must be a finite number between -180.0 and 180.0.',
      );
    }
  }

  /// Creates a [GeoCoordinate] without runtime range checks.
  ///
  /// Useful for compile-time `const` coordinates where values are known to be
  /// within `[-90, 90]` and `[-180, 180]`.
  const GeoCoordinate.unchecked(this.latitude, this.longitude);

  /// Creates a [GeoCoordinate] by clamping [latitude] into `[-90, 90]` and
  /// wrapping [longitude] into `[-180, 180]`.
  factory GeoCoordinate.normalized(double latitude, double longitude) {
    return GeoCoordinate(
      GeoMath.clampLatitude(latitude),
      GeoMath.normalizeLongitude(longitude),
    );
  }

  /// Decodes a Base-32 [geohash] string into its center [GeoCoordinate].
  ///
  /// Throws an [ArgumentError] if [geohash] is empty or contains invalid
  /// Geohash characters.
  factory GeoCoordinate.fromGeohash(String geohash) {
    final bounds = decodeGeohashExtent(geohash);
    return GeoCoordinate(
      (bounds.minLat + bounds.maxLat) / 2.0,
      (bounds.minLon + bounds.maxLon) / 2.0,
    );
  }

  /// Creates a [GeoCoordinate] from a serialized map containing `latitude` and
  /// `longitude` (or `lat` / `lng` / `lon`) numeric fields.
  factory GeoCoordinate.fromMap(Map<String, Object?> map) {
    final latValue = map['latitude'] ?? map['lat'];
    final lonValue = map['longitude'] ?? map['lng'] ?? map['lon'];
    if (latValue is! num || lonValue is! num) {
      throw ArgumentError(
        'Map must contain numeric latitude/longitude keys: $map',
      );
    }
    return GeoCoordinate(latValue.toDouble(), lonValue.toDouble());
  }

  /// Base-32 alphabet defined by the Geohash specification.
  static const String _geohashAlphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Null Island (`0.0, 0.0`).
  static const GeoCoordinate zero = GeoCoordinate.unchecked(0.0, 0.0);

  /// Latitude in decimal degrees `[-90.0, 90.0]`. Positive is North.
  final double latitude;

  /// Longitude in decimal degrees `[-180.0, 180.0]`. Positive is East.
  final double longitude;

  /// Latitude in radians.
  double get latitudeRadians => GeoMath.toRadians(latitude);

  /// Longitude in radians.
  double get longitudeRadians => GeoMath.toRadians(longitude);

  /// Computes the WGS-84 ellipsoidal geodesic solution to [other] using
  /// Vincenty's inverse formula, with automatic spherical fallback for nearly
  /// antipodal points.
  GeodesicResult geodesicTo(GeoCoordinate other) {
    final phi1 = latitudeRadians;
    final phi2 = other.latitudeRadians;
    final rawDeltaLambda = other.longitudeRadians - longitudeRadians;
    // Wrap delta longitude into (-pi, pi] for shortest geodesic across 180°.
    var l = (rawDeltaLambda + math.pi) % (2.0 * math.pi);
    if (l < 0) l += 2.0 * math.pi;
    l -= math.pi;

    if ((phi1 - phi2).abs() < 1e-13 && l.abs() < 1e-13) {
      return const GeodesicResult(
        distanceMeters: 0.0,
        initialBearingDegrees: 0.0,
        finalBearingDegrees: 0.0,
      );
    }

    const a = GeoMath.wgs84A;
    const b = GeoMath.wgs84B;
    const f = GeoMath.wgs84F;

    final tanU1 = (1.0 - f) * math.tan(phi1);
    final cosU1 = 1.0 / math.sqrt(1.0 + tanU1 * tanU1);
    final sinU1 = tanU1 * cosU1;

    final tanU2 = (1.0 - f) * math.tan(phi2);
    final cosU2 = 1.0 / math.sqrt(1.0 + tanU2 * tanU2);
    final sinU2 = tanU2 * cosU2;

    var lambda = l;
    double sinLambda = 0.0;
    double cosLambda = 0.0;
    double sinSigma = 0.0;
    double cosSigma = 0.0;
    double sigma = 0.0;
    double sinAlpha = 0.0;
    double cosSqAlpha = 0.0;
    double cos2SigmaM = 0.0;

    var converged = false;
    for (var i = 0; i < 200; i++) {
      sinLambda = math.sin(lambda);
      cosLambda = math.cos(lambda);
      final term1 = cosU2 * sinLambda;
      final term2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
      sinSigma = math.sqrt(term1 * term1 + term2 * term2);
      if (sinSigma == 0.0) {
        return const GeodesicResult(
          distanceMeters: 0.0,
          initialBearingDegrees: 0.0,
          finalBearingDegrees: 0.0,
        );
      }
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);
      sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
      cosSqAlpha = 1.0 - sinAlpha * sinAlpha;
      cos2SigmaM = cosSqAlpha == 0.0
          ? 0.0
          : cosSigma - 2.0 * sinU1 * sinU2 / cosSqAlpha;
      final c = f / 16.0 * cosSqAlpha * (4.0 + f * (4.0 - 3.0 * cosSqAlpha));
      final lambdaPrev = lambda;
      lambda =
          l +
          (1.0 - c) *
              f *
              sinAlpha *
              (sigma +
                  c *
                      sinSigma *
                      (cos2SigmaM +
                          c *
                              cosSigma *
                              (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
      if ((lambda - lambdaPrev).abs() < 1e-12) {
        converged = true;
        break;
      }
    }

    if (!converged) {
      // Nearly antipodal fallback using spherical math.
      return GeodesicResult(
        distanceMeters: haversineDistanceTo(other),
        initialBearingDegrees: sphericalBearingTo(other),
        finalBearingDegrees: GeoMath.normalizeBearing(
          other.sphericalBearingTo(this) + 180.0,
        ),
        usedEllipsoid: false,
      );
    }

    final uSq = cosSqAlpha * (a * a - b * b) / (b * b);
    final bigA =
        1.0 +
        uSq / 16384.0 * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
    final bigB =
        uSq / 1024.0 * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));
    final deltaSigma =
        bigB *
        sinSigma *
        (cos2SigmaM +
            bigB /
                4.0 *
                (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
                    bigB /
                        6.0 *
                        cos2SigmaM *
                        (-3.0 + 4.0 * sinSigma * sinSigma) *
                        (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));

    final distance = b * bigA * (sigma - deltaSigma);
    final initialAzimuth = math.atan2(
      cosU2 * sinLambda,
      cosU1 * sinU2 - sinU1 * cosU2 * cosLambda,
    );
    final finalAzimuth = math.atan2(
      cosU1 * sinLambda,
      -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda,
    );

    return GeodesicResult(
      distanceMeters: distance,
      initialBearingDegrees: GeoMath.normalizeBearing(
        GeoMath.toDegrees(initialAzimuth),
      ),
      finalBearingDegrees: GeoMath.normalizeBearing(
        GeoMath.toDegrees(finalAzimuth),
      ),
    );
  }

  /// High-precision WGS-84 ellipsoidal distance to [other] in meters.
  double distanceTo(GeoCoordinate other) => geodesicTo(other).distanceMeters;

  /// Fast spherical Haversine distance to [other] in meters.
  double haversineDistanceTo(GeoCoordinate other) {
    final phi1 = latitudeRadians;
    final phi2 = other.latitudeRadians;
    final deltaPhi = phi2 - phi1;
    final deltaLambda = other.longitudeRadians - longitudeRadians;

    final sinHalfLat = math.sin(deltaPhi / 2.0);
    final sinHalfLon = math.sin(deltaLambda / 2.0);
    final h =
        sinHalfLat * sinHalfLat +
        math.cos(phi1) * math.cos(phi2) * sinHalfLon * sinHalfLon;
    final c = 2.0 * math.atan2(math.sqrt(h), math.sqrt(math.max(0.0, 1.0 - h)));
    return GeoMath.meanEarthRadiusMeters * c;
  }

  /// High-precision WGS-84 initial bearing to [other] in degrees `[0, 360)`.
  double bearingTo(GeoCoordinate other) =>
      geodesicTo(other).initialBearingDegrees;

  /// High-precision WGS-84 final bearing arriving at [other] in degrees
  /// `[0, 360)`.
  double finalBearingTo(GeoCoordinate other) =>
      geodesicTo(other).finalBearingDegrees;

  /// Fast spherical initial bearing to [other] in degrees `[0, 360)`.
  double sphericalBearingTo(GeoCoordinate other) {
    final phi1 = latitudeRadians;
    final phi2 = other.latitudeRadians;
    final deltaLambda = other.longitudeRadians - longitudeRadians;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    return GeoMath.normalizeBearing(GeoMath.toDegrees(math.atan2(y, x)));
  }

  /// Computes the destination [GeoCoordinate] reached by travelling
  /// [distanceMeters] along the WGS-84 geodesic starting at [bearingDegrees]
  /// (Vincenty's direct formula).
  GeoCoordinate destinationPoint({
    required double distanceMeters,
    required double bearingDegrees,
  }) {
    if (!distanceMeters.isFinite || !bearingDegrees.isFinite) {
      throw ArgumentError('Distance and bearing must be finite numbers.');
    }
    if (distanceMeters == 0.0) return this;
    if (distanceMeters < 0.0) {
      return destinationPoint(
        distanceMeters: -distanceMeters,
        bearingDegrees: bearingDegrees + 180.0,
      );
    }

    const a = GeoMath.wgs84A;
    const b = GeoMath.wgs84B;
    const f = GeoMath.wgs84F;

    final phi1 = latitudeRadians;
    final lambda1 = longitudeRadians;
    final alpha1 = GeoMath.toRadians(GeoMath.normalizeBearing(bearingDegrees));

    final sinAlpha1 = math.sin(alpha1);
    final cosAlpha1 = math.cos(alpha1);

    final tanU1 = (1.0 - f) * math.tan(phi1);
    final cosU1 = 1.0 / math.sqrt(1.0 + tanU1 * tanU1);
    final sinU1 = tanU1 * cosU1;

    final sigma1 = math.atan2(tanU1, cosAlpha1);
    final sinAlpha = cosU1 * sinAlpha1;
    final cosSqAlpha = 1.0 - sinAlpha * sinAlpha;
    final uSq = cosSqAlpha * (a * a - b * b) / (b * b);
    final bigA =
        1.0 +
        uSq / 16384.0 * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
    final bigB =
        uSq / 1024.0 * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));

    var sigma = distanceMeters / (b * bigA);
    double cos2SigmaM = 0.0;
    double sinSigma = 0.0;
    double cosSigma = 0.0;

    for (var i = 0; i < 200; i++) {
      cos2SigmaM = math.cos(2.0 * sigma1 + sigma);
      sinSigma = math.sin(sigma);
      cosSigma = math.cos(sigma);
      final deltaSigma =
          bigB *
          sinSigma *
          (cos2SigmaM +
              bigB /
                  4.0 *
                  (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
                      bigB /
                          6.0 *
                          cos2SigmaM *
                          (-3.0 + 4.0 * sinSigma * sinSigma) *
                          (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));
      final sigmaPrev = sigma;
      sigma = distanceMeters / (b * bigA) + deltaSigma;
      if ((sigma - sigmaPrev).abs() < 1e-12) break;
    }

    final tmp = sinU1 * sinSigma - cosU1 * cosSigma * cosAlpha1;
    final phi2 = math.atan2(
      sinU1 * cosSigma + cosU1 * sinSigma * cosAlpha1,
      (1.0 - f) * math.sqrt(sinAlpha * sinAlpha + tmp * tmp),
    );
    final lambda = math.atan2(
      sinSigma * sinAlpha1,
      cosU1 * cosSigma - sinU1 * sinSigma * cosAlpha1,
    );
    final c = f / 16.0 * cosSqAlpha * (4.0 + f * (4.0 - 3.0 * cosSqAlpha));
    final l =
        lambda -
        (1.0 - c) *
            f *
            sinAlpha *
            (sigma +
                c *
                    sinSigma *
                    (cos2SigmaM +
                        c * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
    final lambda2 = lambda1 + l;

    return GeoCoordinate.normalized(
      GeoMath.toDegrees(phi2),
      GeoMath.toDegrees(lambda2),
    );
  }

  /// Computes the geographic midpoint along the great circle between `this`
  /// and [other].
  GeoCoordinate midpointTo(GeoCoordinate other) => interpolateTo(other, 0.5);

  /// Spherical linear interpolation (SLERP) along the great circle from `this`
  /// (`fraction = 0.0`) to [other] (`fraction = 1.0`).
  GeoCoordinate interpolateTo(GeoCoordinate other, double fraction) {
    final t = fraction.clamp(0.0, 1.0);
    if (t == 0.0) return this;
    if (t == 1.0) return other;

    final phi1 = latitudeRadians;
    final lambda1 = longitudeRadians;
    final phi2 = other.latitudeRadians;
    final lambda2 = other.longitudeRadians;

    final cosPhi1 = math.cos(phi1);
    final cosPhi2 = math.cos(phi2);
    final delta = haversineDistanceTo(other) / GeoMath.meanEarthRadiusMeters;
    if (delta < 1e-12) return this;

    final sinDelta = math.sin(delta);
    final a = math.sin((1.0 - t) * delta) / sinDelta;
    final b = math.sin(t * delta) / sinDelta;

    final x = a * cosPhi1 * math.cos(lambda1) + b * cosPhi2 * math.cos(lambda2);
    final y = a * cosPhi1 * math.sin(lambda1) + b * cosPhi2 * math.sin(lambda2);
    final z = a * math.sin(phi1) + b * math.sin(phi2);

    final phi = math.atan2(z, math.sqrt(x * x + y * y));
    final lambda = math.atan2(y, x);

    return GeoCoordinate.normalized(
      GeoMath.toDegrees(phi),
      GeoMath.toDegrees(lambda),
    );
  }

  /// Signed perpendicular cross-track distance in meters from `this` point to
  /// the great-circle path defined by [lineStart] -> [lineEnd].
  ///
  /// Positive values indicate the point lies to the right of the path;
  /// negative values indicate it lies to the left.
  double crossTrackDistanceTo(GeoCoordinate lineStart, GeoCoordinate lineEnd) {
    final delta13 =
        lineStart.haversineDistanceTo(this) / GeoMath.meanEarthRadiusMeters;
    final theta13 = GeoMath.toRadians(lineStart.sphericalBearingTo(this));
    final theta12 = GeoMath.toRadians(lineStart.sphericalBearingTo(lineEnd));
    final sinXt = math.sin(delta13) * math.sin(theta13 - theta12);
    return math.asin(sinXt.clamp(-1.0, 1.0)) * GeoMath.meanEarthRadiusMeters;
  }

  /// Along-track distance in meters from [lineStart] to the closest point on
  /// the great-circle path [lineStart] -> [lineEnd].
  double alongTrackDistanceTo(GeoCoordinate lineStart, GeoCoordinate lineEnd) {
    final delta13 =
        lineStart.haversineDistanceTo(this) / GeoMath.meanEarthRadiusMeters;
    final deltaXt =
        crossTrackDistanceTo(lineStart, lineEnd) /
        GeoMath.meanEarthRadiusMeters;
    final cosXt = math.cos(deltaXt);
    if (cosXt.abs() < 1e-12) return 0.0;
    final ratio = (math.cos(delta13) / cosXt).clamp(-1.0, 1.0);
    final deltaAt = math.acos(ratio);
    final theta13 = lineStart.sphericalBearingTo(this);
    final theta12 = lineStart.sphericalBearingTo(lineEnd);
    final angleDiff = GeoMath.shortestAngleDelta(theta12, theta13).abs();
    final sign = angleDiff > 90.0 ? -1.0 : 1.0;
    return sign * deltaAt * GeoMath.meanEarthRadiusMeters;
  }

  /// Encodes this coordinate as a Base-32 Geohash string of length [precision]
  /// (`1` to `12`, default `9` ≈ ±2.4 m precision).
  String toGeohash({int precision = 9}) {
    if (precision < 1 || precision > 12) {
      throw RangeError.range(precision, 1, 12, 'precision');
    }
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLon = -180.0;
    var maxLon = 180.0;
    var isEvenBit = true;
    var bit = 0;
    var ch = 0;
    final buffer = StringBuffer();

    while (buffer.length < precision) {
      if (isEvenBit) {
        final mid = (minLon + maxLon) / 2.0;
        if (longitude >= mid) {
          ch = (ch << 1) | 1;
          minLon = mid;
        } else {
          ch = ch << 1;
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2.0;
        if (latitude >= mid) {
          ch = (ch << 1) | 1;
          minLat = mid;
        } else {
          ch = ch << 1;
          maxLat = mid;
        }
      }
      isEvenBit = !isEvenBit;
      bit++;
      if (bit == 5) {
        buffer.write(_geohashAlphabet[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buffer.toString();
  }

  /// Decodes the latitude/longitude extent record for a Base-32 [geohash].
  static ({double minLat, double minLon, double maxLat, double maxLon})
  decodeGeohashExtent(String geohash) {
    final normalized = geohash.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(geohash, 'geohash', 'Geohash cannot be empty.');
    }
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLon = -180.0;
    var maxLon = 180.0;
    var isEvenBit = true;

    for (var i = 0; i < normalized.length; i++) {
      final charIndex = _geohashAlphabet.indexOf(normalized[i]);
      if (charIndex < 0) {
        throw ArgumentError.value(
          geohash,
          'geohash',
          'Invalid Geohash character "${normalized[i]}" at index $i.',
        );
      }
      for (var mask = 16; mask >= 1; mask >>= 1) {
        final bitSet = (charIndex & mask) != 0;
        if (isEvenBit) {
          final mid = (minLon + maxLon) / 2.0;
          if (bitSet) {
            minLon = mid;
          } else {
            maxLon = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2.0;
          if (bitSet) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEvenBit = !isEvenBit;
      }
    }
    return (minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon);
  }

  /// Returns the 8 surrounding Geohash neighbors keyed by compass code
  /// (`n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`).
  static Map<String, String> geohashNeighbors(String geohash) {
    final normalized = geohash.trim().toLowerCase();
    final extent = decodeGeohashExtent(normalized);
    final precision = normalized.length.clamp(1, 12);
    final lat = (extent.minLat + extent.maxLat) / 2.0;
    final lon = (extent.minLon + extent.maxLon) / 2.0;
    final latSpan = extent.maxLat - extent.minLat;
    final lonSpan = extent.maxLon - extent.minLon;

    String encodeOffset(int dLat, int dLon) {
      final nLat = GeoMath.clampLatitude(lat + dLat * latSpan);
      final nLon = GeoMath.normalizeLongitude(lon + dLon * lonSpan);
      return GeoCoordinate(nLat, nLon).toGeohash(precision: precision);
    }

    return <String, String>{
      'n': encodeOffset(1, 0),
      'ne': encodeOffset(1, 1),
      'e': encodeOffset(0, 1),
      'se': encodeOffset(-1, 1),
      's': encodeOffset(-1, 0),
      'sw': encodeOffset(-1, -1),
      'w': encodeOffset(0, -1),
      'nw': encodeOffset(1, -1),
    };
  }

  /// Formats this coordinate according to [format].
  String format(
    GeoCoordinateFormat format, {
    int fractionDigits = 6,
    int geohashPrecision = 9,
  }) {
    switch (format) {
      case GeoCoordinateFormat.decimalDegrees:
        return '${latitude.toStringAsFixed(fractionDigits)}, '
            '${longitude.toStringAsFixed(fractionDigits)}';
      case GeoCoordinateFormat.decimalDegreesHemisphere:
        final latHemi = latitude >= 0 ? 'N' : 'S';
        final lonHemi = longitude >= 0 ? 'E' : 'W';
        return '${latitude.abs().toStringAsFixed(fractionDigits)}° $latHemi, '
            '${longitude.abs().toStringAsFixed(fractionDigits)}° $lonHemi';
      case GeoCoordinateFormat.degreesDecimalMinutes:
        return '${_formatDdm(latitude, isLat: true)}, '
            '${_formatDdm(longitude, isLat: false)}';
      case GeoCoordinateFormat.degreesMinutesSeconds:
        return '${_formatDms(latitude, isLat: true)}, '
            '${_formatDms(longitude, isLat: false)}';
      case GeoCoordinateFormat.geohash:
        return toGeohash(precision: geohashPrecision);
    }
  }

  static String _formatDdm(double value, {required bool isLat}) {
    final hemi = isLat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final absVal = value.abs();
    final deg = absVal.floor();
    final min = (absVal - deg) * 60.0;
    return "$deg° ${min.toStringAsFixed(4)}' $hemi";
  }

  static String _formatDms(double value, {required bool isLat}) {
    final hemi = isLat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final absVal = value.abs();
    var deg = absVal.floor();
    final remMin = (absVal - deg) * 60.0;
    var min = remMin.floor();
    var sec = (remMin - min) * 60.0;
    if (sec >= 59.995) {
      sec = 0.0;
      min += 1;
      if (min >= 60) {
        min = 0;
        deg += 1;
      }
    }
    return '$deg° $min\' ${sec.toStringAsFixed(2)}" $hemi';
  }

  /// Attempts to parse a coordinate string in decimal degrees, hemisphere
  /// decimal degrees, DDM, or DMS format. Returns `null` if [input] cannot be
  /// parsed into a valid coordinate.
  static GeoCoordinate? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. Plain signed decimal pair: "-6.175392, 106.827153" or "-6.175 106.827"
    final plainRegex = RegExp(
      r'^([+-]?\d+(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d+(?:\.\d+)?)$',
    );
    final plainMatch = plainRegex.firstMatch(trimmed);
    if (plainMatch != null) {
      final lat = double.tryParse(plainMatch.group(1)!);
      final lon = double.tryParse(plainMatch.group(2)!);
      if (lat != null &&
          lon != null &&
          lat >= -90.0 &&
          lat <= 90.0 &&
          lon >= -180.0 &&
          lon <= 180.0) {
        return GeoCoordinate(lat, lon);
      }
      return null;
    }

    // 2. Hemisphere DD / DDM / DMS pairs separated by comma or space.
    final partRegex = RegExp(
      r'''([+-]?\d+(?:\.\d+)?)\s*°?\s*(?:(\d+(?:\.\d+)?)\s*['′])?\s*(?:(\d+(?:\.\d+)?)\s*["″])?\s*([NSEWnsew])''',
    );
    final matches = partRegex.allMatches(trimmed).toList();
    if (matches.length == 2) {
      double? lat;
      double? lon;
      for (final m in matches) {
        final d = double.tryParse(m.group(1)!) ?? 0.0;
        final min = m.group(2) != null
            ? (double.tryParse(m.group(2)!) ?? 0.0)
            : 0.0;
        final sec = m.group(3) != null
            ? (double.tryParse(m.group(3)!) ?? 0.0)
            : 0.0;
        final dir = m.group(4)!.toUpperCase();
        var value = d.abs() + min / 60.0 + sec / 3600.0;
        if (dir == 'S' || dir == 'W' || d < 0) value = -value;
        if (dir == 'N' || dir == 'S') {
          lat = value;
        } else {
          lon = value;
        }
      }
      if (lat != null &&
          lon != null &&
          lat >= -90.0 &&
          lat <= 90.0 &&
          lon >= -180.0 &&
          lon <= 180.0) {
        return GeoCoordinate(lat, lon);
      }
    }
    return null;
  }

  /// Returns a copy with updated [latitude] and/or [longitude].
  GeoCoordinate copyWith({double? latitude, double? longitude}) {
    return GeoCoordinate(
      latitude ?? this.latitude,
      longitude ?? this.longitude,
    );
  }

  /// Serializes this coordinate into a JSON-compatible map.
  Map<String, double> toMap() => <String, double>{
    'latitude': latitude,
    'longitude': longitude,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoCoordinate &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoCoordinate(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';
}
