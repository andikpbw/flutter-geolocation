import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo_coordinate.dart';
import '../core/geo_geometry.dart';
import '../core/geo_position.dart';

/// Transition type emitted by [GeofenceEngine].
enum GeofenceTransition {
  /// The device crossed from outside to inside the geofence.
  enter,

  /// The device remained inside the geofence for at least
  /// [GeofenceRegion.dwellDuration].
  dwell,

  /// The device crossed from inside to outside the geofence (beyond any
  /// configured [GeofenceRegion.hysteresisMeters]).
  exit,
}

/// Abstract base class for monitored geographic geofence regions.
@immutable
sealed class GeofenceRegion {
  /// Creates a [GeofenceRegion].
  const GeofenceRegion({
    required this.id,
    this.name,
    this.hysteresisMeters = 0.0,
    this.dwellDuration,
    this.metadata = const <String, Object?>{},
  }) : assert(hysteresisMeters >= 0.0, 'hysteresisMeters must be >= 0');

  /// Unique identifier for this geofence.
  final String id;

  /// Optional human-friendly display label.
  final String? name;

  /// Extra buffer distance outside the perimeter required before firing an
  /// [GeofenceTransition.exit] event, eliminating boundary flapping caused by
  /// GPS jitter.
  final double hysteresisMeters;

  /// Optional duration the device must stay inside before firing a
  /// [GeofenceTransition.dwell] event.
  final Duration? dwellDuration;

  /// Arbitrary developer metadata associated with this region.
  final Map<String, Object?> metadata;

  /// Representative center coordinate of this region.
  GeoCoordinate get center;

  /// Signed geodesic distance in meters from [coordinate] to the region's
  /// boundary:
  /// - Negative (`< 0`) when strictly inside,
  /// - `0` on the boundary,
  /// - Positive (`> 0`) when strictly outside.
  double signedDistanceMeters(GeoCoordinate coordinate);

  /// Returns `true` if [coordinate] lies inside or on the boundary.
  bool contains(GeoCoordinate coordinate) =>
      signedDistanceMeters(coordinate) <= 0.0;
}

/// Circular geofence defined by a [center] coordinate and [radiusMeters].
@immutable
final class CircularGeofence extends GeofenceRegion {
  /// Creates a [CircularGeofence].
  CircularGeofence({
    required super.id,
    required this.center,
    required this.radiusMeters,
    super.name,
    super.hysteresisMeters = 0.0,
    super.dwellDuration,
    super.metadata = const <String, Object?>{},
  }) {
    if (!radiusMeters.isFinite || radiusMeters <= 0) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Radius must be finite and greater than 0.',
      );
    }
  }

  @override
  final GeoCoordinate center;

  /// Radius of the circular zone in meters.
  final double radiusMeters;

  @override
  double signedDistanceMeters(GeoCoordinate coordinate) {
    return center.distanceTo(coordinate) - radiusMeters;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CircularGeofence &&
        other.id == id &&
        other.center == center &&
        other.radiusMeters == radiusMeters &&
        other.hysteresisMeters == hysteresisMeters &&
        other.dwellDuration == dwellDuration;
  }

  @override
  int get hashCode =>
      Object.hash(id, center, radiusMeters, hysteresisMeters, dwellDuration);
}

/// Polygonal geofence defined by an arbitrary closed [GeoPolygon].
@immutable
final class PolygonGeofence extends GeofenceRegion {
  /// Creates a [PolygonGeofence].
  const PolygonGeofence({
    required super.id,
    required this.polygon,
    super.name,
    super.hysteresisMeters = 0.0,
    super.dwellDuration,
    super.metadata = const <String, Object?>{},
  });

  /// Polygon defining the monitored perimeter.
  final GeoPolygon polygon;

  @override
  GeoCoordinate get center => polygon.centroid;

  @override
  double signedDistanceMeters(GeoCoordinate coordinate) {
    final dist = polygon.distanceToBoundaryMeters(coordinate);
    return polygon.contains(coordinate) ? -dist : dist;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PolygonGeofence &&
        other.id == id &&
        other.polygon == polygon &&
        other.hysteresisMeters == hysteresisMeters &&
        other.dwellDuration == dwellDuration;
  }

  @override
  int get hashCode => Object.hash(id, polygon, hysteresisMeters, dwellDuration);
}

/// Event emitted when a device enters, dwells within, or exits a
/// [GeofenceRegion].
@immutable
class GeofenceEvent {
  /// Creates a [GeofenceEvent].
  const GeofenceEvent({
    required this.region,
    required this.transition,
    required this.position,
    required this.distanceToBoundaryMeters,
    required this.timestamp,
  });

  /// The geofence region that triggered this event.
  final GeofenceRegion region;

  /// Transition type (`enter`, `dwell`, or `exit`).
  final GeofenceTransition transition;

  /// Position fix that caused this transition.
  final GeoPosition position;

  /// Unsigned distance in meters from [position] to the region's boundary.
  final double distanceToBoundaryMeters;

  /// UTC timestamp of the transition.
  final DateTime timestamp;

  @override
  String toString() =>
      'GeofenceEvent(${region.id}: ${transition.name}, '
      'dist=${distanceToBoundaryMeters.toStringAsFixed(1)}m)';
}

class _RegionState {
  bool isInside = false;
  DateTime? enteredAt;
  bool hasDwelled = false;
}

/// Real-time geofencing engine evaluating [CircularGeofence] and
/// [PolygonGeofence] regions with boundary hysteresis and dwell detection.
class GeofenceEngine {
  /// Creates a [GeofenceEngine] optionally pre-populated with [regions].
  GeofenceEngine({
    Iterable<GeofenceRegion> regions = const <GeofenceRegion>[],
  }) {
    for (final region in regions) {
      addRegion(region);
    }
  }

  final Map<String, GeofenceRegion> _regions = <String, GeofenceRegion>{};
  final Map<String, _RegionState> _states = <String, _RegionState>{};
  final StreamController<GeofenceEvent> _controller =
      StreamController<GeofenceEvent>.broadcast();

  bool _disposed = false;

  /// Broadcast stream of [GeofenceEvent] transitions.
  Stream<GeofenceEvent> get events => _controller.stream;

  /// Currently registered geofence regions.
  List<GeofenceRegion> get regions =>
      List<GeofenceRegion>.unmodifiable(_regions.values);

  /// Regions that the device is currently considered to be inside.
  List<GeofenceRegion> get activeRegions => List<GeofenceRegion>.unmodifiable(
    _regions.values.where((r) => _states[r.id]?.isInside ?? false),
  );

  /// Returns `true` if the device is currently inside the region with [id].
  bool isInside(String id) => _states[id]?.isInside ?? false;

  /// Registers or replaces a [GeofenceRegion].
  void addRegion(GeofenceRegion region) {
    _regions[region.id] = region;
    _states.putIfAbsent(region.id, _RegionState.new);
  }

  /// Removes the region matching [id]. Returns `true` if a region was removed.
  bool removeRegion(String id) {
    _states.remove(id);
    return _regions.remove(id) != null;
  }

  /// Removes all registered regions and resets state.
  void clear() {
    _regions.clear();
    _states.clear();
  }

  /// Evaluates [position] against every registered region, emits any triggered
  /// [GeofenceEvent]s onto [events], and also returns them synchronously.
  List<GeofenceEvent> processPosition(GeoPosition position) {
    if (_disposed) return const <GeofenceEvent>[];

    final triggered = <GeofenceEvent>[];
    for (final region in _regions.values) {
      final state = _states.putIfAbsent(region.id, _RegionState.new);
      final signed = region.signedDistanceMeters(position.coordinate);

      if (!state.isInside) {
        if (signed <= 0.0) {
          state.isInside = true;
          state.enteredAt = position.timestamp;
          state.hasDwelled = false;
          final event = GeofenceEvent(
            region: region,
            transition: GeofenceTransition.enter,
            position: position,
            distanceToBoundaryMeters: signed.abs(),
            timestamp: position.timestamp,
          );
          triggered.add(event);
          _emit(event);

          // Handle zero-duration dwell immediately if configured.
          if (region.dwellDuration != null &&
              region.dwellDuration! <= Duration.zero) {
            state.hasDwelled = true;
            final dwellEvent = GeofenceEvent(
              region: region,
              transition: GeofenceTransition.dwell,
              position: position,
              distanceToBoundaryMeters: signed.abs(),
              timestamp: position.timestamp,
            );
            triggered.add(dwellEvent);
            _emit(dwellEvent);
          }
        }
      } else {
        if (signed > region.hysteresisMeters) {
          state.isInside = false;
          state.enteredAt = null;
          state.hasDwelled = false;
          final event = GeofenceEvent(
            region: region,
            transition: GeofenceTransition.exit,
            position: position,
            distanceToBoundaryMeters: signed.abs(),
            timestamp: position.timestamp,
          );
          triggered.add(event);
          _emit(event);
        } else if (!state.hasDwelled &&
            region.dwellDuration != null &&
            state.enteredAt != null &&
            position.timestamp.difference(state.enteredAt!) >=
                region.dwellDuration!) {
          state.hasDwelled = true;
          final dwellEvent = GeofenceEvent(
            region: region,
            transition: GeofenceTransition.dwell,
            position: position,
            distanceToBoundaryMeters: signed.abs(),
            timestamp: position.timestamp,
          );
          triggered.add(dwellEvent);
          _emit(dwellEvent);
        }
      }
    }
    return triggered;
  }

  void _emit(GeofenceEvent event) {
    if (!_disposed && !_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Releases resources and closes the [events] stream.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
