import 'package:flutter_geolocation/flutter_geolocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoCoordinate validation & construction', () {
    test('accepts valid boundary coordinates', () {
      expect(GeoCoordinate(90.0, 180.0).latitude, 90.0);
      expect(GeoCoordinate(-90.0, -180.0).longitude, -180.0);
      expect(GeoCoordinate.zero, const GeoCoordinate.unchecked(0.0, 0.0));
    });

    test('rejects invalid or non-finite coordinates', () {
      expect(() => GeoCoordinate(90.001, 0.0), throwsArgumentError);
      expect(() => GeoCoordinate(-91.0, 0.0), throwsArgumentError);
      expect(() => GeoCoordinate(0.0, 180.1), throwsArgumentError);
      expect(() => GeoCoordinate(0.0, -180.1), throwsArgumentError);
      expect(() => GeoCoordinate(double.nan, 0.0), throwsArgumentError);
      expect(() => GeoCoordinate(0.0, double.infinity), throwsArgumentError);
    });

    test('normalized factory clamps latitude and wraps longitude', () {
      final c = GeoCoordinate.normalized(95.0, 190.0);
      expect(c.latitude, 90.0);
      expect(c.longitude, closeTo(-170.0, 1e-9));

      final c2 = GeoCoordinate.normalized(-95.0, -185.0);
      expect(c2.latitude, -90.0);
      expect(c2.longitude, closeTo(175.0, 1e-9));
    });

    test('fromMap and toMap round-trip cleanly', () {
      final original = GeoCoordinate(-6.175392, 106.827153);
      final restored = GeoCoordinate.fromMap(original.toMap());
      expect(restored, original);
      expect(
        GeoCoordinate.fromMap(<String, Object?>{'lat': 1.25, 'lng': 103.85}),
        GeoCoordinate(1.25, 103.85),
      );
      expect(
        () => GeoCoordinate.fromMap(<String, Object?>{'lat': 'invalid'}),
        throwsArgumentError,
      );
    });
  });

  group('WGS-84 Vincenty & Spherical Geodesy', () {
    test('matches official Geoscience Australia Vincenty benchmark', () {
      // Flinders Peak to Buninyong official WGS-84 benchmark: 54,972.271 m.
      final flinders = GeoCoordinate(-37.9510334167, 144.4248678889);
      final buninyong = GeoCoordinate(-37.6528211389, 143.9264955278);

      final result = flinders.geodesicTo(buninyong);
      expect(result.usedEllipsoid, isTrue);
      expect(result.distanceMeters, closeTo(54972.271, 0.01));
      expect(result.initialBearingDegrees, closeTo(306.86816, 0.001));
      expect(result.finalBearingDegrees, closeTo(307.17363, 0.001));
      expect(result.distanceKilometers, closeTo(54.972271, 1e-5));
      expect(result.distanceMiles, closeTo(34.15818, 1e-3));
      expect(result.distanceNauticalMiles, closeTo(29.68265, 1e-3));
    });

    test('Vincenty direct formula round-trips accurately', () {
      final monas = GeoCoordinate(-6.175392, 106.827153);
      final dest = monas.destinationPoint(
        distanceMeters: 25000.0,
        bearingDegrees: 73.5,
      );
      final inverse = monas.geodesicTo(dest);
      expect(inverse.distanceMeters, closeTo(25000.0, 0.01));
      expect(inverse.initialBearingDegrees, closeTo(73.5, 0.001));
    });

    test('handles coincident, antimeridian, and nearly antipodal points', () {
      final p = GeoCoordinate(-6.175392, 106.827153);
      expect(p.distanceTo(p), 0.0);
      expect(p.destinationPoint(distanceMeters: 0, bearingDegrees: 90), p);

      // Crossing antimeridian: 179.9° E to 179.9° W at equator ≈ 22.26 km.
      final westOfDateLine = GeoCoordinate(0.0, 179.9);
      final eastOfDateLine = GeoCoordinate(0.0, -179.9);
      expect(westOfDateLine.distanceTo(eastOfDateLine), closeTo(22263.9, 5.0));
      expect(westOfDateLine.bearingTo(eastOfDateLine), closeTo(90.0, 0.01));

      // Nearly antipodal points must never return NaN.
      final a = GeoCoordinate(0.0, 0.0);
      final b = GeoCoordinate(0.0, 179.999999);
      final antipodal = a.geodesicTo(b);
      expect(antipodal.distanceMeters.isFinite, isTrue);
      expect(antipodal.distanceMeters, greaterThan(19900000.0));
    });

    test(
      'SLERP interpolation, midpoint, cross-track, and along-track work',
      () {
        final a = GeoCoordinate(0.0, 0.0);
        final b = GeoCoordinate(0.0, 10.0);
        final mid = a.midpointTo(b);
        expect(mid.latitude, closeTo(0.0, 1e-6));
        expect(mid.longitude, closeTo(5.0, 1e-6));

        final northOffset = GeoCoordinate(0.01, 5.0);
        // Point lies north (left) of eastward equatorial line -> negative XT.
        final xt = northOffset.crossTrackDistanceTo(a, b);
        expect(xt, lessThan(-1000.0));
        expect(xt.abs(), closeTo(1111.95, 5.0));

        final at = northOffset.alongTrackDistanceTo(a, b);
        expect(at, closeTo(a.haversineDistanceTo(mid), 15.0));
      },
    );
  });

  group('Geohash, Formatting, Parsing & CompassDirection', () {
    test('encodes, decodes, and resolves 8 neighbors accurately', () {
      final monas = GeoCoordinate(-6.175392, 106.827153);
      final hash = monas.toGeohash(precision: 9);
      expect(hash.length, 9);
      final decoded = GeoCoordinate.fromGeohash(hash);
      expect(monas.distanceTo(decoded), lessThan(5.0));

      final neighbors = GeoCoordinate.geohashNeighbors(hash);
      expect(
        neighbors.keys,
        containsAll(<String>['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']),
      );
      expect(neighbors['n'], isNot(hash));

      expect(() => monas.toGeohash(precision: 0), throwsRangeError);
      expect(() => GeoCoordinate.fromGeohash(''), throwsArgumentError);
      expect(() => GeoCoordinate.fromGeohash('invalid!'), throwsArgumentError);
    });

    test('formats DD, DDM, DMS, Geohash and parses them back', () {
      final monas = GeoCoordinate(-6.175392, 106.827153);

      final dd = monas.format(GeoCoordinateFormat.decimalDegrees);
      expect(dd, '-6.175392, 106.827153');
      expect(GeoCoordinate.tryParse(dd)!.distanceTo(monas), lessThan(0.2));

      final ddHemi = monas.format(GeoCoordinateFormat.decimalDegreesHemisphere);
      expect(ddHemi, '6.175392° S, 106.827153° E');
      expect(GeoCoordinate.tryParse(ddHemi)!.distanceTo(monas), lessThan(0.2));

      final ddm = monas.format(GeoCoordinateFormat.degreesDecimalMinutes);
      expect(GeoCoordinate.tryParse(ddm)!.distanceTo(monas), lessThan(1.0));

      final dms = monas.format(GeoCoordinateFormat.degreesMinutesSeconds);
      expect(GeoCoordinate.tryParse(dms)!.distanceTo(monas), lessThan(1.0));

      expect(GeoCoordinate.tryParse('not a coordinate'), isNull);
      expect(GeoCoordinate.tryParse('95.0, 10.0'), isNull);
    });

    test('CompassDirection & GeoMath utilities', () {
      expect(CompassDirection.fromBearing(0), CompassDirection.north);
      expect(CompassDirection.fromBearing(359.9), CompassDirection.north);
      expect(CompassDirection.fromBearing(90), CompassDirection.east);
      expect(CompassDirection.fromBearing(225), CompassDirection.southwest);
      expect(CompassDirection.fromBearing8Point(20), CompassDirection.north);
      expect(
        CompassDirection.fromBearing8Point(45),
        CompassDirection.northeast,
      );

      expect(GeoMath.shortestAngleDelta(350, 10), closeTo(20.0, 1e-9));
      expect(GeoMath.shortestAngleDelta(10, 350), closeTo(-20.0, 1e-9));
      expect(GeoMath.formatDistanceMetric(8.4), '8.4 m');
      expect(GeoMath.formatDistanceMetric(350), '350 m');
      expect(GeoMath.formatDistanceMetric(2450), '2.45 km');
      expect(GeoMath.formatDistanceImperial(100), '328 ft');
      expect(GeoMath.formatDistanceImperial(1609.344), '1.00 mi');
    });
  });
}
