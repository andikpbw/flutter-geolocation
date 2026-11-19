import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/geo_bounds.dart';
import '../core/geo_geometry.dart';
import '../core/geo_position.dart';

/// Lifecycle state of a [GeoTrackRecorder].
enum GeoTrackState {
  /// Recorder has not been started or has been reset.
  idle,

  /// Actively appending incoming positions.
  recording,

  /// Temporarily paused; incoming fixes are ignored until resumed.
  paused,

  /// Recording completed; statistics and exports remain readable.
  stopped,
}

/// Immutable summary statistics for a recorded GPS track.
@immutable
class GeoTrackStats {
  /// Creates a [GeoTrackStats] snapshot.
  const GeoTrackStats({
    required this.pointCount,
    required this.totalDistanceMeters,
    required this.elapsedDuration,
    required this.movingDuration,
    required this.averageSpeedMetersPerSecond,
    required this.movingAverageSpeedMetersPerSecond,
    required this.maxSpeedMetersPerSecond,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
    this.minAltitudeMeters,
    this.maxAltitudeMeters,
    this.bounds,
  });

  /// Empty statistics snapshot when no points have been recorded.
  static const GeoTrackStats empty = GeoTrackStats(
    pointCount: 0,
    totalDistanceMeters: 0.0,
    elapsedDuration: Duration.zero,
    movingDuration: Duration.zero,
    averageSpeedMetersPerSecond: 0.0,
    movingAverageSpeedMetersPerSecond: 0.0,
    maxSpeedMetersPerSecond: 0.0,
    elevationGainMeters: 0.0,
    elevationLossMeters: 0.0,
  );

  /// Total number of recorded fixes.
  final int pointCount;

  /// Cumulative WGS-84 geodesic distance traveled in meters.
  final double totalDistanceMeters;

  /// Total elapsed time between the first and last recorded fix.
  final Duration elapsedDuration;

  /// Cumulative duration spent moving above the stationary speed threshold.
  final Duration movingDuration;

  /// Overall average speed (`totalDistanceMeters / elapsedDuration`) in `m/s`.
  final double averageSpeedMetersPerSecond;

  /// Average speed while actively moving in `m/s`.
  final double movingAverageSpeedMetersPerSecond;

  /// Peak recorded speed in `m/s`.
  final double maxSpeedMetersPerSecond;

  /// Cumulative positive elevation climb in meters.
  final double elevationGainMeters;

  /// Cumulative elevation descent in meters (positive magnitude).
  final double elevationLossMeters;

  /// Minimum recorded altitude in meters, or `null` if no points recorded.
  final double? minAltitudeMeters;

  /// Maximum recorded altitude in meters, or `null` if no points recorded.
  final double? maxAltitudeMeters;

  /// Geographic bounding box of the track, or `null` if empty.
  final GeoBounds? bounds;

  /// Total distance in kilometers.
  double get totalDistanceKilometers => totalDistanceMeters / 1000.0;

  /// Overall average speed in `km/h`.
  double get averageSpeedKmh => averageSpeedMetersPerSecond * 3.6;

  /// Moving average speed in `km/h`.
  double get movingAverageSpeedKmh => movingAverageSpeedMetersPerSecond * 3.6;

  /// Peak speed in `km/h`.
  double get maxSpeedKmh => maxSpeedMetersPerSecond * 3.6;
}

/// Records GPS position fixes into a structured route with live statistics,
/// elevation analytics, Douglas-Peucker simplification, GeoJSON, and GPX export.
class GeoTrackRecorder {
  /// Creates a [GeoTrackRecorder].
  ///
  /// - [minDisplacementMeters] filters out stationary jitter below this
  ///   distance threshold.
  /// - [maxAccuracyMeters] discards fixes with horizontal accuracy worse than
  ///   this threshold (when `position.accuracy > 0`).
  /// - [movingSpeedThresholdMetersPerSecond] classifies segments above this
  ///   velocity as active movement for `movingDuration`.
  GeoTrackRecorder({
    this.minDisplacementMeters = 1.5,
    this.maxAccuracyMeters = 50.0,
    this.movingSpeedThresholdMetersPerSecond = 0.5,
  });

  /// Minimum movement in meters required to append a new track point.
  final double minDisplacementMeters;

  /// Maximum acceptable horizontal accuracy radius in meters.
  final double maxAccuracyMeters;

  /// Minimum velocity in `m/s` considered active movement.
  final double movingSpeedThresholdMetersPerSecond;

  final List<GeoPosition> _points = <GeoPosition>[];
  GeoTrackState _state = GeoTrackState.idle;
  double _totalDistanceMeters = 0.0;
  Duration _movingDuration = Duration.zero;
  double _maxSpeed = 0.0;
  double _elevationGain = 0.0;
  double _elevationLoss = 0.0;
  double? _minAltitude;
  double? _maxAltitude;
  bool _segmentBreak = false;

  /// Current lifecycle state of the recorder.
  GeoTrackState get state => _state;

  /// Unmodifiable list of recorded [GeoPosition] points.
  List<GeoPosition> get points => List<GeoPosition>.unmodifiable(_points);

  /// Route geometry represented as a [GeoPolyline].
  GeoPolyline get polyline => GeoPolyline(_points.map((p) => p.coordinate));

  /// Starts a fresh recording session (clears any previous track).
  void start() {
    reset();
    _state = GeoTrackState.recording;
  }

  /// Pauses recording without clearing existing points.
  void pause() {
    if (_state == GeoTrackState.recording) {
      _state = GeoTrackState.paused;
      _segmentBreak = true;
    }
  }

  /// Resumes a paused recording session.
  void resume() {
    if (_state == GeoTrackState.paused) {
      _state = GeoTrackState.recording;
    }
  }

  /// Stops recording while preserving collected points and statistics.
  void stop() {
    if (_state == GeoTrackState.recording || _state == GeoTrackState.paused) {
      _state = GeoTrackState.stopped;
    }
  }

  /// Clears all recorded points and returns the recorder to [GeoTrackState.idle].
  void reset() {
    _points.clear();
    _state = GeoTrackState.idle;
    _totalDistanceMeters = 0.0;
    _movingDuration = Duration.zero;
    _maxSpeed = 0.0;
    _elevationGain = 0.0;
    _elevationLoss = 0.0;
    _minAltitude = null;
    _maxAltitude = null;
    _segmentBreak = false;
  }

  /// Adds a [position] if the recorder is [GeoTrackState.recording] and the
  /// fix passes accuracy & displacement filters.
  ///
  /// Returns `true` if the point was accepted and appended.
  bool record(GeoPosition position) {
    if (_state != GeoTrackState.recording) return false;
    if (position.accuracy > 0 && position.accuracy > maxAccuracyMeters) {
      return false;
    }

    if (_points.isNotEmpty && !_segmentBreak) {
      final prev = _points.last;
      final dist = prev.coordinate.distanceTo(position.coordinate);
      if (dist < minDisplacementMeters) {
        return false;
      }

      _totalDistanceMeters += dist;
      final dt = position.timestamp.difference(prev.timestamp);
      if (dt > Duration.zero) {
        final derivedSpeed = dist / (dt.inMilliseconds / 1000.0);
        final effectiveSpeed = position.speed > 0
            ? position.speed
            : derivedSpeed;
        if (effectiveSpeed >= movingSpeedThresholdMetersPerSecond) {
          _movingDuration += dt;
        }
        _maxSpeed = math.max(_maxSpeed, effectiveSpeed);
      }

      final altDelta = position.altitude - prev.altitude;
      // Ignore tiny altitude fluctuations (< 1m) from barometric/GPS drift.
      if (altDelta > 1.0) {
        _elevationGain += altDelta;
      } else if (altDelta < -1.0) {
        _elevationLoss += altDelta.abs();
      }
    } else {
      _segmentBreak = false;
      _maxSpeed = math.max(_maxSpeed, position.speed);
    }

    _minAltitude = _minAltitude == null
        ? position.altitude
        : math.min(_minAltitude!, position.altitude);
    _maxAltitude = _maxAltitude == null
        ? position.altitude
        : math.max(_maxAltitude!, position.altitude);

    _points.add(position);
    return true;
  }

  /// Current computed [GeoTrackStats] snapshot.
  GeoTrackStats get stats {
    if (_points.isEmpty) return GeoTrackStats.empty;
    final elapsed = _points.length >= 2
        ? _points.last.timestamp.difference(_points.first.timestamp)
        : Duration.zero;
    final elapsedSec = elapsed.inMilliseconds / 1000.0;
    final movingSec = _movingDuration.inMilliseconds / 1000.0;

    return GeoTrackStats(
      pointCount: _points.length,
      totalDistanceMeters: _totalDistanceMeters,
      elapsedDuration: elapsed > Duration.zero ? elapsed : Duration.zero,
      movingDuration: _movingDuration,
      averageSpeedMetersPerSecond: elapsedSec > 0
          ? _totalDistanceMeters / elapsedSec
          : 0.0,
      movingAverageSpeedMetersPerSecond: movingSec > 0
          ? _totalDistanceMeters / movingSec
          : 0.0,
      maxSpeedMetersPerSecond: _maxSpeed,
      elevationGainMeters: _elevationGain,
      elevationLossMeters: _elevationLoss,
      minAltitudeMeters: _minAltitude,
      maxAltitudeMeters: _maxAltitude,
      bounds: GeoBounds.fromCoordinates(_points.map((p) => p.coordinate)),
    );
  }

  /// Exports the recorded track as a valid RFC 7946 GeoJSON `FeatureCollection`
  /// string. Optionally simplifies the track with [simplifyToleranceMeters].
  String toGeoJson({
    String name = 'Recorded Track',
    double? simplifyToleranceMeters,
  }) {
    final currentStats = stats;
    final coords =
        simplifyToleranceMeters != null && simplifyToleranceMeters > 0
        ? polyline
              .simplify(simplifyToleranceMeters)
              .points
              .map((c) => <double>[c.longitude, c.latitude])
              .toList(growable: false)
        : _points
              .map((p) => <double>[p.longitude, p.latitude, p.altitude])
              .toList(growable: false);

    final featureCollection = <String, Object?>{
      'type': 'FeatureCollection',
      'features': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'Feature',
          'properties': <String, Object?>{
            'name': name,
            'pointCount': currentStats.pointCount,
            'totalDistanceMeters': currentStats.totalDistanceMeters,
            'elapsedSeconds': currentStats.elapsedDuration.inSeconds,
            'movingSeconds': currentStats.movingDuration.inSeconds,
            'maxSpeedMetersPerSecond': currentStats.maxSpeedMetersPerSecond,
            'elevationGainMeters': currentStats.elevationGainMeters,
            'elevationLossMeters': currentStats.elevationLossMeters,
          },
          'geometry': <String, Object?>{
            'type': 'LineString',
            'coordinates': coords,
          },
        },
      ],
    };
    return jsonEncode(featureCollection);
  }

  /// Exports the recorded track as a GPX 1.1 XML string.
  String toGpx({
    String name = 'Recorded Track',
    String creator = 'geolocator_flutter',
  }) {
    final escapedName = _escapeXml(name);
    final escapedCreator = _escapeXml(creator);
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="$escapedCreator" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <trk>')
      ..writeln('    <name>$escapedName</name>')
      ..writeln('    <trkseg>');

    for (final p in _points) {
      buf
        ..writeln(
          '      <trkpt lat="${p.latitude.toStringAsFixed(7)}" '
          'lon="${p.longitude.toStringAsFixed(7)}">',
        )
        ..writeln('        <ele>${p.altitude.toStringAsFixed(2)}</ele>')
        ..writeln(
          '        <time>${p.timestamp.toUtc().toIso8601String()}</time>',
        )
        ..writeln('      </trkpt>');
    }

    buf
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buf.toString();
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
