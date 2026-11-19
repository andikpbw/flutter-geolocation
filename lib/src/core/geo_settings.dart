import 'package:flutter/foundation.dart';

/// Desired horizontal accuracy level for location requests.
enum GeoAccuracy {
  /// Lowest accuracy (~500m–3km), minimal battery usage (cell / passive).
  lowest,

  /// Low accuracy (~500m), city-block level.
  low,

  /// Balanced accuracy (~100m), Wi-Fi + cell triangulation.
  medium,

  /// High accuracy (~10m–30m), GNSS enabled.
  high,

  /// Best available accuracy (~3m–10m), high-frequency GNSS.
  best,

  /// Navigation-grade accuracy combining GNSS and motion sensors.
  navigation,
}

/// Operating system authorization status for location access.
enum GeoPermissionStatus {
  /// Permission has not been granted yet (can still prompt the user).
  denied,

  /// Permission was permanently denied; user must enable it in OS settings.
  deniedForever,

  /// Permission granted only while the application is in the foreground.
  whileInUse,

  /// Permission granted for both foreground and background location updates.
  always,

  /// Platform cannot inspect permission status beforehand (e.g. legacy web).
  unableToDetermine;

  /// Returns `true` when location access is granted (`whileInUse` or `always`).
  bool get isGranted =>
      this == GeoPermissionStatus.whileInUse ||
      this == GeoPermissionStatus.always;

  /// Parses a string status identifier returned by native platforms.
  static GeoPermissionStatus fromName(String? value) {
    switch (value?.toLowerCase()) {
      case 'always':
        return GeoPermissionStatus.always;
      case 'whileinuse':
      case 'while_in_use':
      case 'granted':
        return GeoPermissionStatus.whileInUse;
      case 'deniedforever':
      case 'denied_forever':
      case 'restricted':
        return GeoPermissionStatus.deniedForever;
      case 'denied':
      case 'prompt':
        return GeoPermissionStatus.denied;
      default:
        return GeoPermissionStatus.unableToDetermine;
    }
  }
}

/// Operating system global location service availability state.
enum GeoServiceStatus {
  /// Device location services are turned on.
  enabled,

  /// Device location services are turned off.
  disabled;

  /// Parses a string or boolean representation into a [GeoServiceStatus].
  static GeoServiceStatus fromValue(Object? value) {
    if (value is bool) {
      return value ? GeoServiceStatus.enabled : GeoServiceStatus.disabled;
    }
    if (value is String && value.toLowerCase() == 'enabled') {
      return GeoServiceStatus.enabled;
    }
    return GeoServiceStatus.disabled;
  }
}

/// Configuration options for single-fix and continuous location tracking.
@immutable
class GeoSettings {
  /// Creates a [GeoSettings] configuration.
  const GeoSettings({
    this.accuracy = GeoAccuracy.high,
    this.distanceFilterMeters = 0.0,
    this.timeInterval = const Duration(seconds: 1),
    this.timeout,
    this.enableKalmanFilter = false,
    this.kalmanProcessNoise = 3.0,
    this.maxAcceptedSpeedMetersPerSecond = 120.0,
    this.allowMockLocations = true,
    this.forceLocationManager = false,
  }) : assert(distanceFilterMeters >= 0.0, 'distanceFilterMeters must be >= 0');

  /// Preset tuned for battery-friendly background or coarse discovery.
  static const GeoSettings balanced = GeoSettings(
    accuracy: GeoAccuracy.medium,
    distanceFilterMeters: 25.0,
    timeInterval: Duration(seconds: 5),
  );

  /// Preset tuned for real-time navigation with adaptive Kalman smoothing.
  static const GeoSettings navigation = GeoSettings(
    accuracy: GeoAccuracy.navigation,
    distanceFilterMeters: 2.0,
    timeInterval: Duration(milliseconds: 500),
    enableKalmanFilter: true,
    kalmanProcessNoise: 2.5,
  );

  /// Desired location precision.
  final GeoAccuracy accuracy;

  /// Minimum distance in meters the device must move before emitting an update.
  final double distanceFilterMeters;

  /// Desired minimum time interval between consecutive position updates.
  final Duration timeInterval;

  /// Optional maximum time to wait for a position fix before throwing
  /// `GeoTimeoutException`.
  final Duration? timeout;

  /// Whether to smooth incoming position streams through `GeoKalmanFilter`.
  final bool enableKalmanFilter;

  /// Process noise parameter (Q) when [enableKalmanFilter] is enabled.
  final double kalmanProcessNoise;

  /// Maximum plausible speed in `m/s` used to reject impossible GPS spikes
  /// when [enableKalmanFilter] is enabled.
  final double maxAcceptedSpeedMetersPerSecond;

  /// Whether fixes flagged with `isMocked == true` are allowed through.
  /// When `false`, mocked fixes are filtered out of streams and rejected on
  /// single-fix requests.
  final bool allowMockLocations;

  /// On Android, forces use of the platform `LocationManager` directly.
  final bool forceLocationManager;

  /// Returns a copy with overridden properties.
  GeoSettings copyWith({
    GeoAccuracy? accuracy,
    double? distanceFilterMeters,
    Duration? timeInterval,
    Duration? timeout,
    bool? enableKalmanFilter,
    double? kalmanProcessNoise,
    double? maxAcceptedSpeedMetersPerSecond,
    bool? allowMockLocations,
    bool? forceLocationManager,
  }) {
    return GeoSettings(
      accuracy: accuracy ?? this.accuracy,
      distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
      timeInterval: timeInterval ?? this.timeInterval,
      timeout: timeout ?? this.timeout,
      enableKalmanFilter: enableKalmanFilter ?? this.enableKalmanFilter,
      kalmanProcessNoise: kalmanProcessNoise ?? this.kalmanProcessNoise,
      maxAcceptedSpeedMetersPerSecond:
          maxAcceptedSpeedMetersPerSecond ??
          this.maxAcceptedSpeedMetersPerSecond,
      allowMockLocations: allowMockLocations ?? this.allowMockLocations,
      forceLocationManager: forceLocationManager ?? this.forceLocationManager,
    );
  }

  /// Serializes settings into a platform-channel argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    'accuracy': accuracy.name,
    'distanceFilterMeters': distanceFilterMeters,
    'timeIntervalMs': timeInterval.inMilliseconds,
    if (timeout != null) 'timeoutMs': timeout!.inMilliseconds,
    'allowMockLocations': allowMockLocations,
    'forceLocationManager': forceLocationManager,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoSettings &&
        other.accuracy == accuracy &&
        other.distanceFilterMeters == distanceFilterMeters &&
        other.timeInterval == timeInterval &&
        other.timeout == timeout &&
        other.enableKalmanFilter == enableKalmanFilter &&
        other.kalmanProcessNoise == kalmanProcessNoise &&
        other.maxAcceptedSpeedMetersPerSecond ==
            maxAcceptedSpeedMetersPerSecond &&
        other.allowMockLocations == allowMockLocations &&
        other.forceLocationManager == forceLocationManager;
  }

  @override
  int get hashCode => Object.hash(
    accuracy,
    distanceFilterMeters,
    timeInterval,
    timeout,
    enableKalmanFilter,
    kalmanProcessNoise,
    maxAcceptedSpeedMetersPerSecond,
    allowMockLocations,
    forceLocationManager,
  );
}
