import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_flutter/geolocator_flutter.dart';

void main() {
  group('GeoBounds', () {
    test(
      'computes bounds, center, containment, expansion, and intersection',
      () {
        final center = GeoCoordinate(-6.175392, 106.827153);
        final bounds = GeoBounds.fromCenterAndRadius(center, 500.0);

        expect(bounds.contains(center), isTrue);
        expect(bounds.crossesAntimeridian, isFalse);
        expect(bounds.widthMeters, closeTo(1000.0, 5.0));
        expect(bounds.heightMeters, closeTo(1000.0, 5.0));

        final expanded = bounds.expandBy(250.0);
        expect(expanded.heightMeters, closeTo(1500.0, 10.0));
        expect(bounds.intersects(expanded), isTrue);

        final far = GeoBounds.fromCenterAndRadius(
          GeoCoordinate(35.6762, 139.6503),
          500.0,
        );
        expect(bounds.intersects(far), isFalse);
      },
    );

    test('handles antimeridian crossing cleanly', () {
      final crossing = GeoBounds(
        southWest: GeoCoordinate(-10.0, 175.0),
        northEast: GeoCoordinate(10.0, -175.0),
      );
      expect(crossing.crossesAntimeridian, isTrue);
      expect(crossing.contains(GeoCoordinate(0.0, 179.0)), isTrue);
      expect(crossing.contains(GeoCoordinate(0.0, -178.0)), isTrue);
      expect(crossing.contains(GeoCoordinate(0.0, 0.0)), isFalse);
      expect(crossing.center.longitude.abs(), closeTo(180.0, 1e-6));
    });
  });

  group('GeoPolyline', () {
    test(
      'measures total length, simplifies with RDP, and detects off-route',
      () {
        final start = GeoCoordinate(0.0, 0.0);
        final midOnLine = GeoCoordinate(0.0, 0.005);
        final end = GeoCoordinate(0.0, 0.01);
        final route = GeoPolyline(<GeoCoordinate>[start, midOnLine, end]);

        expect(route.totalLengthMeters, closeTo(start.distanceTo(end), 0.5));

        // Colinear middle point collapses cleanly under 5m tolerance.
        final simplified = route.simplify(5.0);
        expect(simplified.length, 2);

        // Significant corner survives simplification.
        final bentRoute = GeoPolyline(<GeoCoordinate>[
          start,
          GeoCoordinate(0.002, 0.005), // ~222m deviation
          end,
        ]);
        expect(bentRoute.simplify(50.0).length, 3);

        // Snapping & off-route detection.
        final near = GeoCoordinate(0.0001, 0.005); // ~11m north
        final snap = route.nearestPointTo(near);
        expect(snap.distanceMeters, closeTo(11.1, 1.0));
        expect(route.isOffRoute(near, 25.0), isFalse);
        expect(route.isOffRoute(near, 5.0), isTrue);

        final geoJson = route.toGeoJsonGeometry();
        expect(geoJson['type'], 'LineString');
      },
    );
  });

  group('GeoPolygon', () {
    test('tests point-in-polygon, boundary, perimeter, and geodesic area', () {
      // 1° x 1° equatorial square ≈ 12,308 km².
      final square = GeoPolygon(<GeoCoordinate>[
        GeoCoordinate(0.0, 0.0),
        GeoCoordinate(0.0, 1.0),
        GeoCoordinate(1.0, 1.0),
        GeoCoordinate(1.0, 0.0),
        GeoCoordinate(
          0.0,
          0.0,
        ), // Duplicate closing vertex trimmed automatically.
      ]);

      expect(square.vertices.length, 4);
      expect(square.contains(GeoCoordinate(0.5, 0.5)), isTrue);
      expect(square.contains(GeoCoordinate(0.0, 0.5)), isTrue); // On edge.
      expect(square.contains(GeoCoordinate(1.5, 0.5)), isFalse);
      expect(square.areaSquareKilometers, closeTo(12308.0, 100.0));
      expect(square.perimeterMeters, greaterThan(440000.0));
      expect(
        square.distanceToBoundaryMeters(GeoCoordinate(0.5, 0.5)),
        greaterThan(55000.0),
      );

      final geoJson = square.toGeoJsonGeometry();
      expect(geoJson['type'], 'Polygon');
    });

    test('supports concave L-shaped polygons accurately', () {
      final lShape = GeoPolygon(<GeoCoordinate>[
        GeoCoordinate(0.0, 0.0),
        GeoCoordinate(0.0, 2.0),
        GeoCoordinate(1.0, 2.0),
        GeoCoordinate(1.0, 1.0),
        GeoCoordinate(2.0, 1.0),
        GeoCoordinate(2.0, 0.0),
      ]);

      expect(lShape.contains(GeoCoordinate(0.5, 1.5)), isTrue);
      expect(lShape.contains(GeoCoordinate(1.5, 0.5)), isTrue);
      expect(lShape.contains(GeoCoordinate(1.5, 1.5)), isFalse); // Cutout!
    });
  });
}
