import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'geo_bounds.dart';
import 'geo_coordinate.dart';

/// Result of projecting a coordinate onto a [GeoPolyline].
@immutable
class PolylineSnapResult {
  /// Creates a [PolylineSnapResult].
  const PolylineSnapResult({
    required this.closestPoint,
    required this.distanceMeters,
    required this.segmentIndex,
    required this.distanceAlongPathMeters,
  });

  /// Closest projected point on the polyline.
  final GeoCoordinate closestPoint;

  /// Perpendicular or endpoint distance from the query point to [closestPoint].
  final double distanceMeters;

  /// Zero-based index of the segment `[segmentIndex, segmentIndex + 1]`.
  final int segmentIndex;

  /// Cumulative distance from the start of the polyline to [closestPoint].
  final double distanceAlongPathMeters;
}

/// An ordered sequence of [GeoCoordinate] vertices representing a path or
/// route, with geodesic length, Douglas-Peucker simplification, and nearest
/// point snapping.
@immutable
class GeoPolyline {
  /// Creates a [GeoPolyline] from an ordered list of [points].
  GeoPolyline(Iterable<GeoCoordinate> points)
    : points = List<GeoCoordinate>.unmodifiable(points);

  /// Ordered vertices along the polyline.
  final List<GeoCoordinate> points;

  /// Whether this polyline has fewer than 2 points.
  bool get isEmpty => points.isEmpty;

  /// Number of vertices in the polyline.
  int get length => points.length;

  /// Total geodesic length of the polyline in meters.
  double get totalLengthMeters {
    if (points.length < 2) return 0.0;
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += points[i - 1].distanceTo(points[i]);
    }
    return sum;
  }

  /// Bounding box enclosing all vertices, or `null` if [points] is empty.
  GeoBounds? get bounds =>
      points.isEmpty ? null : GeoBounds.fromCoordinates(points);

  /// Simplifies this polyline using the Ramer-Douglas-Peucker algorithm with
  /// a perpendicular cross-track distance threshold of [toleranceMeters].
  GeoPolyline simplify(double toleranceMeters) {
    if (!toleranceMeters.isFinite ||
        toleranceMeters <= 0 ||
        points.length <= 2) {
      return this;
    }
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    _rdp(0, points.length - 1, toleranceMeters, keep);
    final simplified = <GeoCoordinate>[];
    for (var i = 0; i < points.length; i++) {
      if (keep[i]) simplified.add(points[i]);
    }
    return GeoPolyline(simplified);
  }

  void _rdp(int start, int end, double tolerance, List<bool> keep) {
    if (end - start <= 1) return;
    var maxDistance = -1.0;
    var maxIndex = start;
    final a = points[start];
    final b = points[end];
    final segLen = a.haversineDistanceTo(b);

    for (var i = start + 1; i < end; i++) {
      final double d;
      if (segLen < 1e-6) {
        d = points[i].haversineDistanceTo(a);
      } else {
        d = _distanceToSegment(points[i], a, b).distanceMeters;
      }
      if (d > maxDistance) {
        maxDistance = d;
        maxIndex = i;
      }
    }

    if (maxDistance > tolerance) {
      keep[maxIndex] = true;
      _rdp(start, maxIndex, tolerance, keep);
      _rdp(maxIndex, end, tolerance, keep);
    }
  }

  /// Projects [coordinate] onto the nearest segment of this polyline.
  ///
  /// Throws a [StateError] if [points] is empty.
  PolylineSnapResult nearestPointTo(GeoCoordinate coordinate) {
    if (points.isEmpty) {
      throw StateError('Cannot project onto an empty GeoPolyline.');
    }
    if (points.length == 1) {
      return PolylineSnapResult(
        closestPoint: points.first,
        distanceMeters: coordinate.distanceTo(points.first),
        segmentIndex: 0,
        distanceAlongPathMeters: 0.0,
      );
    }

    var bestDistance = double.infinity;
    var bestPoint = points.first;
    var bestIndex = 0;
    var bestAlong = 0.0;
    var cumulative = 0.0;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segLen = a.distanceTo(b);
      final proj = _distanceToSegment(coordinate, a, b);
      if (proj.distanceMeters < bestDistance) {
        bestDistance = proj.distanceMeters;
        bestPoint = proj.point;
        bestIndex = i;
        bestAlong = cumulative + proj.fraction * segLen;
      }
      cumulative += segLen;
    }

    return PolylineSnapResult(
      closestPoint: bestPoint,
      distanceMeters: bestDistance,
      segmentIndex: bestIndex,
      distanceAlongPathMeters: bestAlong,
    );
  }

  /// Returns `true` if [coordinate] deviates from this route by more than
  /// [maxDeviationMeters].
  bool isOffRoute(GeoCoordinate coordinate, double maxDeviationMeters) {
    if (points.isEmpty) return true;
    return nearestPointTo(coordinate).distanceMeters > maxDeviationMeters;
  }

  static ({GeoCoordinate point, double distanceMeters, double fraction})
  _distanceToSegment(GeoCoordinate p, GeoCoordinate a, GeoCoordinate b) {
    final segLen = a.haversineDistanceTo(b);
    if (segLen < 1e-6) {
      return (point: a, distanceMeters: p.distanceTo(a), fraction: 0.0);
    }
    final along = p.alongTrackDistanceTo(a, b);
    if (along <= 0.0) {
      return (point: a, distanceMeters: p.distanceTo(a), fraction: 0.0);
    }
    if (along >= segLen) {
      return (point: b, distanceMeters: p.distanceTo(b), fraction: 1.0);
    }
    final fraction = (along / segLen).clamp(0.0, 1.0);
    final projected = a.interpolateTo(b, fraction);
    return (
      point: projected,
      distanceMeters: p.distanceTo(projected),
      fraction: fraction,
    );
  }

  /// Converts this polyline into a GeoJSON `LineString` geometry map.
  Map<String, Object?> toGeoJsonGeometry() => <String, Object?>{
    'type': 'LineString',
    'coordinates': points
        .map((p) => <double>[p.longitude, p.latitude])
        .toList(growable: false),
  };
}

/// A closed geographic polygon supporting point-in-polygon testing,
/// boundary distance measurement, and spherical-excess geodesic area.
@immutable
class GeoPolygon {
  /// Creates a [GeoPolygon] from at least 3 [vertices].
  ///
  /// The polygon is automatically closed (an explicit duplicate closing vertex
  /// is trimmed so edge iteration remains uniform).
  GeoPolygon(Iterable<GeoCoordinate> vertices)
    : vertices = _normalizeVertices(vertices);

  static List<GeoCoordinate> _normalizeVertices(Iterable<GeoCoordinate> input) {
    final list = input.toList(growable: true);
    if (list.length > 1 && list.first == list.last) {
      list.removeLast();
    }
    if (list.length < 3) {
      throw ArgumentError(
        'A GeoPolygon requires at least 3 distinct vertices.',
      );
    }
    return List<GeoCoordinate>.unmodifiable(list);
  }

  /// Ordered vertices defining the outer ring of this polygon.
  final List<GeoCoordinate> vertices;

  /// Bounding box enclosing this polygon.
  GeoBounds get bounds => GeoBounds.fromCoordinates(vertices);

  /// Centroid (arithmetic mean) of the polygon's vertices.
  GeoCoordinate get centroid {
    var sumLat = 0.0;
    var sumLon = 0.0;
    for (final v in vertices) {
      sumLat += v.latitude;
      sumLon += v.longitude;
    }
    return GeoCoordinate.normalized(
      sumLat / vertices.length,
      sumLon / vertices.length,
    );
  }

  /// Total geodesic perimeter of this polygon in meters.
  double get perimeterMeters {
    var total = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final next = (i + 1) % vertices.length;
      total += vertices[i].distanceTo(vertices[next]);
    }
    return total;
  }

  /// Geodesic surface area of the polygon in square meters (`m²`), computed
  /// via spherical excess (Chamberlain & Duquette formula).
  double get areaSquareMeters {
    var sum = 0.0;
    final count = vertices.length;
    for (var i = 0; i < count; i++) {
      final p1 = vertices[i];
      final p2 = vertices[(i + 1) % count];
      final p3 = vertices[(i + 2) % count];
      sum +=
          (p3.longitudeRadians - p1.longitudeRadians) *
          math.sin(p2.latitudeRadians);
    }
    const r = GeoMath.meanEarthRadiusMeters;
    return (sum.abs() * r * r) / 2.0;
  }

  /// Geodesic surface area in square kilometers (`km²`).
  double get areaSquareKilometers => areaSquareMeters / 1e6;

  /// Returns `true` if [coordinate] is inside or on the boundary of this
  /// polygon using ray casting with segment-boundary tolerance.
  bool contains(GeoCoordinate coordinate) {
    if (!bounds.contains(coordinate)) return false;

    final px = coordinate.longitude;
    final py = coordinate.latitude;
    var inside = false;
    final n = vertices.length;

    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = vertices[i].longitude;
      final yi = vertices[i].latitude;
      final xj = vertices[j].longitude;
      final yj = vertices[j].latitude;

      // Check exact boundary colinearity within epsilon.
      if (_isPointOnSegment(px, py, xi, yi, xj, yj)) {
        return true;
      }

      final intersects =
          ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Shortest geodesic distance in meters from [coordinate] to the polygon's
  /// perimeter edges.
  double distanceToBoundaryMeters(GeoCoordinate coordinate) {
    final closed = <GeoCoordinate>[...vertices, vertices.first];
    return GeoPolyline(closed).nearestPointTo(coordinate).distanceMeters;
  }

  static bool _isPointOnSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    const eps = 1e-10;
    final cross = (py - ay) * (bx - ax) - (px - ax) * (by - ay);
    if (cross.abs() > eps) return false;
    final minX = math.min(ax, bx) - eps;
    final maxX = math.max(ax, bx) + eps;
    final minY = math.min(ay, by) - eps;
    final maxY = math.max(ay, by) + eps;
    return px >= minX && px <= maxX && py >= minY && py <= maxY;
  }

  /// Converts this polygon into a GeoJSON `Polygon` geometry map.
  Map<String, Object?> toGeoJsonGeometry() {
    final ring = <List<double>>[
      ...vertices.map((p) => <double>[p.longitude, p.latitude]),
      <double>[vertices.first.longitude, vertices.first.latitude],
    ];
    return <String, Object?>{
      'type': 'Polygon',
      'coordinates': <List<List<double>>>[ring],
    };
  }
}
