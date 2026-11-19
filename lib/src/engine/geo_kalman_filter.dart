import 'dart:math' as math;

import '../core/geo_coordinate.dart';
import '../core/geo_position.dart';

/// Adaptive 2D metric-plane Kalman filter for smoothing noisy GPS streams
/// while rejecting physically impossible teleportation spikes.
///
/// Operates in a local East-North-Up (ENU) metric tangent plane anchored at
/// the first fix so longitude scaling remains accurate at all latitudes.
class GeoKalmanFilter {
  /// Creates a [GeoKalmanFilter].
  ///
  /// - [processNoiseMetersPerSecond] controls responsiveness vs. smoothing
  ///   (higher values track sudden turns faster; lower values smooth more).
  /// - [minAccuracyMeters] prevents over-trusting optimistic `0m` accuracy
  ///   reports.
  /// - [maxSpeedMetersPerSecond] rejects single-frame GPS jumps exceeding this
  ///   plausible velocity. After [reanchorAfterConsecutiveOutliers] consecutive
  ///   rejections, the filter automatically re-anchors so legitimate jumps
  ///   (e.g. exiting a tunnel or airplane mode) never lock the filter.
  GeoKalmanFilter({
    this.processNoiseMetersPerSecond = 3.0,
    this.minAccuracyMeters = 2.0,
    this.maxSpeedMetersPerSecond = 120.0,
    this.reanchorAfterConsecutiveOutliers = 3,
  }) : assert(
         processNoiseMetersPerSecond > 0,
         'processNoiseMetersPerSecond must be > 0',
       ),
       assert(minAccuracyMeters > 0, 'minAccuracyMeters must be > 0'),
       assert(
         maxSpeedMetersPerSecond > 0,
         'maxSpeedMetersPerSecond must be > 0',
       );

  /// Base process velocity standard deviation in meters per second.
  final double processNoiseMetersPerSecond;

  /// Floor applied to incoming horizontal accuracy values in meters.
  final double minAccuracyMeters;

  /// Speed threshold in `m/s` above which a single fix is treated as an
  /// outlier spike.
  final double maxSpeedMetersPerSecond;

  /// Number of consecutive outlier fixes before forcibly re-anchoring state.
  final int reanchorAfterConsecutiveOutliers;

  static const double _metersPerLatDegree = 111319.49079327358;

  GeoCoordinate? _anchor;
  double _x = 0.0; // Easting in meters relative to _anchor
  double _y = 0.0; // Northing in meters relative to _anchor
  double _variance = -1.0; // Position variance in m^2
  DateTime? _lastTimestamp;
  GeoPosition? _lastOutput;
  int _consecutiveOutliers = 0;

  /// Most recent filtered position, or `null` if no fix has been processed.
  GeoPosition? get lastPosition => _lastOutput;

  /// Resets all internal filter state.
  void reset() {
    _anchor = null;
    _x = 0.0;
    _y = 0.0;
    _variance = -1.0;
    _lastTimestamp = null;
    _lastOutput = null;
    _consecutiveOutliers = 0;
  }

  /// Processes a raw [position] and returns the Kalman-smoothed [GeoPosition].
  ///
  /// Returns `null` if [position] is rejected as a transient outlier spike.
  GeoPosition? process(GeoPosition position) {
    final accuracy = math.max(
      minAccuracyMeters,
      position.accuracy > 0 ? position.accuracy : minAccuracyMeters * 2.0,
    );

    if (_variance < 0 || _anchor == null || _lastTimestamp == null) {
      _anchor = position.coordinate;
      _x = 0.0;
      _y = 0.0;
      _variance = accuracy * accuracy;
      _lastTimestamp = position.timestamp;
      _consecutiveOutliers = 0;
      _lastOutput = position;
      return position;
    }

    final dtMs = position.timestamp.difference(_lastTimestamp!).inMilliseconds;
    final dtSec = dtMs > 0 ? dtMs / 1000.0 : 0.0;

    // Check for impossible GPS spike before updating.
    if (_lastOutput != null && dtSec > 0.0) {
      final jumpDistance = _lastOutput!.coordinate.haversineDistanceTo(
        position.coordinate,
      );
      final impliedSpeed = jumpDistance / dtSec;
      if (impliedSpeed > maxSpeedMetersPerSecond &&
          jumpDistance > accuracy * 3) {
        _consecutiveOutliers++;
        if (_consecutiveOutliers < reanchorAfterConsecutiveOutliers) {
          return null;
        }
        // Legitimate relocation after several consistent fixes -> re-anchor.
        _anchor = position.coordinate;
        _x = 0.0;
        _y = 0.0;
        _variance = accuracy * accuracy;
        _lastTimestamp = position.timestamp;
        _consecutiveOutliers = 0;
        _lastOutput = position;
        return position;
      }
    }
    _consecutiveOutliers = 0;

    // Convert incoming WGS-84 point to local ENU meters relative to _anchor.
    final anchor = _anchor!;
    final cosLat = math.max(1e-6, math.cos(GeoMath.toRadians(anchor.latitude)));
    final metersPerLonDegree = _metersPerLatDegree * cosLat;

    var deltaLon = position.longitude - anchor.longitude;
    if (deltaLon > 180.0) deltaLon -= 360.0;
    if (deltaLon < -180.0) deltaLon += 360.0;

    final measX = deltaLon * metersPerLonDegree;
    final measY = (position.latitude - anchor.latitude) * _metersPerLatDegree;

    // Prediction step: inflate variance according to elapsed time & motion.
    if (dtSec > 0.0) {
      final qVel = math.max(processNoiseMetersPerSecond, position.speed);
      _variance += dtSec * qVel * qVel;
    }

    // Measurement update step.
    final measVariance = accuracy * accuracy;
    final kalmanGain = _variance / (_variance + measVariance);

    final prevX = _x;
    final prevY = _y;
    _x += kalmanGain * (measX - _x);
    _y += kalmanGain * (measY - _y);
    _variance = (1.0 - kalmanGain) * _variance;
    _lastTimestamp = position.timestamp;

    final filteredLat = GeoMath.clampLatitude(
      anchor.latitude + _y / _metersPerLatDegree,
    );
    final filteredLon = GeoMath.normalizeLongitude(
      anchor.longitude + _x / metersPerLonDegree,
    );
    final filteredCoord = GeoCoordinate(filteredLat, filteredLon);

    // Derive heading & speed when raw sensor values are absent.
    var filteredHeading = position.heading;
    var filteredSpeed = position.speed;
    final movedDx = _x - prevX;
    final movedDy = _y - prevY;
    final movedDist = math.sqrt(movedDx * movedDx + movedDy * movedDy);
    if (dtSec > 0.0 && movedDist > 0.3) {
      if (filteredSpeed <= 0.0) {
        filteredSpeed = movedDist / dtSec;
      }
      if (filteredHeading == 0.0 && position.headingAccuracy == 0.0) {
        filteredHeading = GeoMath.normalizeBearing(
          GeoMath.toDegrees(math.atan2(movedDx, movedDy)),
        );
      }
    }

    final result = position.copyWith(
      coordinate: filteredCoord,
      accuracy: math.sqrt(_variance),
      heading: filteredHeading,
      speed: filteredSpeed,
    );
    _lastOutput = result;
    return result;
  }
}
