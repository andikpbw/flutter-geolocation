import 'package:flutter/foundation.dart';

import 'geo_coordinate.dart';

/// An immutable geographic bounding box defined by its [southWest] and
/// [northEast] corners, supporting antimeridian (`±180°` longitude) crossings.
@immutable
class GeoBounds {
  /// Creates a [GeoBounds] with validated south/north latitude ordering.
  ///
  /// When `southWest.longitude > northEast.longitude`, the bounds are treated
  /// as spanning across the `±180°` antimeridian.
  GeoBounds({required this.southWest, required this.northEast}) {
    if (southWest.latitude > northEast.latitude) {
      throw ArgumentError(
        'southWest.latitude (${southWest.latitude}) cannot be greater than '
        'northEast.latitude (${northEast.latitude}).',
      );
    }
  }

  /// Computes the minimal bounding box containing all [coordinates].
  ///
  /// Throws an [ArgumentError] if [coordinates] is empty.
  factory GeoBounds.fromCoordinates(Iterable<GeoCoordinate> coordinates) {
    final iterator = coordinates.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError('coordinates must not be empty.');
    }
    var minLat = iterator.current.latitude;
    var maxLat = iterator.current.latitude;
    var minLon = iterator.current.longitude;
    var maxLon = iterator.current.longitude;

    while (iterator.moveNext()) {
      final c = iterator.current;
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    return GeoBounds(
      southWest: GeoCoordinate(minLat, minLon),
      northEast: GeoCoordinate(maxLat, maxLon),
    );
  }

  /// Creates a square-in-meters bounding box centered at [center] extending
  /// [radiusMeters] north, south, east, and west along WGS-84 geodesics.
  factory GeoBounds.fromCenterAndRadius(
    GeoCoordinate center,
    double radiusMeters,
  ) {
    if (!radiusMeters.isFinite || radiusMeters < 0) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Radius must be finite and non-negative.',
      );
    }
    if (radiusMeters == 0) {
      return GeoBounds(southWest: center, northEast: center);
    }
    final north = center.destinationPoint(
      distanceMeters: radiusMeters,
      bearingDegrees: 0.0,
    );
    final east = center.destinationPoint(
      distanceMeters: radiusMeters,
      bearingDegrees: 90.0,
    );
    final south = center.destinationPoint(
      distanceMeters: radiusMeters,
      bearingDegrees: 180.0,
    );
    final west = center.destinationPoint(
      distanceMeters: radiusMeters,
      bearingDegrees: 270.0,
    );
    return GeoBounds(
      southWest: GeoCoordinate(south.latitude, west.longitude),
      northEast: GeoCoordinate(north.latitude, east.longitude),
    );
  }

  /// Southwest corner of the bounding box.
  final GeoCoordinate southWest;

  /// Northeast corner of the bounding box.
  final GeoCoordinate northEast;

  /// Whether this bounding box crosses the `±180°` antimeridian.
  bool get crossesAntimeridian => southWest.longitude > northEast.longitude;

  /// Northwest corner of the bounding box.
  GeoCoordinate get northWest =>
      GeoCoordinate(northEast.latitude, southWest.longitude);

  /// Southeast corner of the bounding box.
  GeoCoordinate get southEast =>
      GeoCoordinate(southWest.latitude, northEast.longitude);

  /// Geographic center of the bounding box.
  GeoCoordinate get center {
    final lat = (southWest.latitude + northEast.latitude) / 2.0;
    double lon;
    if (!crossesAntimeridian) {
      lon = (southWest.longitude + northEast.longitude) / 2.0;
    } else {
      final span =
          (180.0 - southWest.longitude) + (northEast.longitude + 180.0);
      lon = GeoMath.normalizeLongitude(southWest.longitude + span / 2.0);
    }
    return GeoCoordinate(lat, lon);
  }

  /// Approximate east-west width in meters measured across [center]'s latitude.
  double get widthMeters {
    final midLat = (southWest.latitude + northEast.latitude) / 2.0;
    if (!crossesAntimeridian) {
      return GeoCoordinate(
        midLat,
        southWest.longitude,
      ).distanceTo(GeoCoordinate(midLat, northEast.longitude));
    }
    final toDateLine = GeoCoordinate(
      midLat,
      southWest.longitude,
    ).distanceTo(GeoCoordinate(midLat, 180.0));
    final fromDateLine = GeoCoordinate(
      midLat,
      -180.0,
    ).distanceTo(GeoCoordinate(midLat, northEast.longitude));
    return toDateLine + fromDateLine;
  }

  /// North-south height in meters along the central meridian.
  double get heightMeters {
    final midLon = center.longitude;
    return GeoCoordinate(
      southWest.latitude,
      midLon,
    ).distanceTo(GeoCoordinate(northEast.latitude, midLon));
  }

  /// Returns `true` if [coordinate] lies inside or on the boundary of this box.
  bool contains(GeoCoordinate coordinate) {
    if (coordinate.latitude < southWest.latitude ||
        coordinate.latitude > northEast.latitude) {
      return false;
    }
    if (!crossesAntimeridian) {
      return coordinate.longitude >= southWest.longitude &&
          coordinate.longitude <= northEast.longitude;
    }
    return coordinate.longitude >= southWest.longitude ||
        coordinate.longitude <= northEast.longitude;
  }

  /// Returns `true` if this bounding box overlaps [other].
  bool intersects(GeoBounds other) {
    final latOverlap =
        southWest.latitude <= other.northEast.latitude &&
        northEast.latitude >= other.southWest.latitude;
    if (!latOverlap) return false;

    if (!crossesAntimeridian && !other.crossesAntimeridian) {
      return southWest.longitude <= other.northEast.longitude &&
          northEast.longitude >= other.southWest.longitude;
    }
    if (crossesAntimeridian && other.crossesAntimeridian) {
      return true;
    }
    final crossing = crossesAntimeridian ? this : other;
    final normal = crossesAntimeridian ? other : this;
    return normal.northEast.longitude >= crossing.southWest.longitude ||
        normal.southWest.longitude <= crossing.northEast.longitude;
  }

  /// Returns a new [GeoBounds] expanded outward in all directions by [meters].
  GeoBounds expandBy(double meters) {
    if (!meters.isFinite || meters < 0) {
      throw ArgumentError.value(meters, 'meters', 'Must be >= 0 and finite.');
    }
    if (meters == 0) return this;
    final north = northEast.destinationPoint(
      distanceMeters: meters,
      bearingDegrees: 0.0,
    );
    final east = northEast.destinationPoint(
      distanceMeters: meters,
      bearingDegrees: 90.0,
    );
    final south = southWest.destinationPoint(
      distanceMeters: meters,
      bearingDegrees: 180.0,
    );
    final west = southWest.destinationPoint(
      distanceMeters: meters,
      bearingDegrees: 270.0,
    );
    return GeoBounds(
      southWest: GeoCoordinate(south.latitude, west.longitude),
      northEast: GeoCoordinate(north.latitude, east.longitude),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoBounds &&
        other.southWest == southWest &&
        other.northEast == northEast;
  }

  @override
  int get hashCode => Object.hash(southWest, northEast);

  @override
  String toString() => 'GeoBounds(sw: $southWest, ne: $northEast)';
}
