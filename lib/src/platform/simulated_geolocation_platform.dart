import 'dart:async';
import 'dart:math' as math;

import '../core/geo_coordinate.dart';
import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import 'geolocation_platform.dart';

/// Deterministic, realistic GPS route simulator implementing
/// [GeolocationPlatform].
///
/// Ideal for unit tests, widget tests, desktop previews, and live demos
/// without requiring physical GPS hardware. Supports smooth geodesic
/// interpolation along waypoints, configurable speed, accuracy jitter, and
/// looping playback.
class SimulatedGeolocationPlatform extends GeolocationPlatform {
  /// Creates a [SimulatedGeolocationPlatform] traveling along [route].
  ///
  /// If [route] is empty, defaults to a scenic loop around Monas, Jakarta.
  SimulatedGeolocationPlatform({
    List<GeoCoordinate>? route,
    this.speedMetersPerSecond = 14.0,
    this.updateInterval = const Duration(milliseconds: 250),
    this.baseAccuracyMeters = 4.2,
    this.jitterMeters = 0.8,
    this.baseAltitudeMeters = 18.0,
    this.loop = true,
    this.serviceEnabled = true,
    this.permissionStatus = GeoPermissionStatus.whileInUse,
    int seed = 42,
  }) : route = List<GeoCoordinate>.unmodifiable(
         route != null && route.isNotEmpty ? route : defaultJakartaRoute,
       ),
       _random = math.Random(seed);

  /// Default scenic urban loop around Central Jakarta (Monas -> Thamrin ->
  /// Merdeka Square) used when no custom route is provided.
  static const List<GeoCoordinate> defaultJakartaRoute = <GeoCoordinate>[
    GeoCoordinate.unchecked(-6.17665, 106.82495),
    GeoCoordinate.unchecked(-6.17539, 106.82715),
    GeoCoordinate.unchecked(-6.17360, 106.82860),
    GeoCoordinate.unchecked(-6.17290, 106.82610),
    GeoCoordinate.unchecked(-6.17435, 106.82420),
    GeoCoordinate.unchecked(-6.17665, 106.82495),
  ];

  /// Ordered waypoints along which the simulated device travels.
  final List<GeoCoordinate> route;

  /// Simulated cruising speed in meters per second.
  final double speedMetersPerSecond;

  /// Time step between emitted positions.
  final Duration updateInterval;

  /// Baseline horizontal accuracy radius in meters.
  final double baseAccuracyMeters;

  /// Optional random Gaussian-like GPS noise amplitude in meters (`0` for
  /// noise-free deterministic coordinates).
  final double jitterMeters;

  /// Baseline altitude in meters.
  final double baseAltitudeMeters;

  /// Whether playback loops seamlessly back to the start of [route].
  final bool loop;

  /// Simulated location service status.
  bool serviceEnabled;

  /// Simulated permission status.
  GeoPermissionStatus permissionStatus;

  final math.Random _random;
  final StreamController<GeoServiceStatus> _serviceStatusController =
      StreamController<GeoServiceStatus>.broadcast();

  double _distanceTraveledMeters = 0.0;
  GeoPosition? _lastPosition;
  int _tickCount = 0;

  /// Toggles the simulated location service and notifies listeners.
  void setServiceEnabled(bool enabled) {
    serviceEnabled = enabled;
    if (!_serviceStatusController.isClosed) {
      _serviceStatusController.add(
        enabled ? GeoServiceStatus.enabled : GeoServiceStatus.disabled,
      );
    }
  }

  /// Resets simulated route progress back to the starting waypoint.
  void resetRoute() {
    _distanceTraveledMeters = 0.0;
    _lastPosition = null;
    _tickCount = 0;
  }

  /// Computes the simulated [GeoPosition] at a specific route progress
  /// [distanceMeters] without relying on wall-clock timers.
  GeoPosition positionAtDistance(
    double distanceMeters, {
    DateTime? timestamp,
    bool includeJitter = true,
  }) {
    final now = (timestamp ?? DateTime.now()).toUtc();
    if (route.length == 1) {
      return GeoPosition.fromLatLng(
        latitude: route.first.latitude,
        longitude: route.first.longitude,
        timestamp: now,
        accuracy: baseAccuracyMeters,
        altitude: baseAltitudeMeters,
        heading: 0.0,
        speed: 0.0,
        provider: GeoProvider.simulated,
      );
    }

    final segmentLengths = <double>[];
    var totalLength = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final len = route[i].distanceTo(route[i + 1]);
      segmentLengths.add(len);
      totalLength += len;
    }

    if (totalLength <= 0.0) {
      return GeoPosition.fromLatLng(
        latitude: route.first.latitude,
        longitude: route.first.longitude,
        timestamp: now,
        accuracy: baseAccuracyMeters,
        altitude: baseAltitudeMeters,
        provider: GeoProvider.simulated,
      );
    }

    var remaining = loop
        ? distanceMeters % totalLength
        : distanceMeters.clamp(0.0, totalLength);
    var segIdx = 0;
    while (segIdx < segmentLengths.length - 1 &&
        remaining > segmentLengths[segIdx]) {
      remaining -= segmentLengths[segIdx];
      segIdx++;
    }

    final segStart = route[segIdx];
    final segEnd = route[segIdx + 1];
    final segLen = segmentLengths[segIdx];
    final fraction = segLen > 0 ? (remaining / segLen).clamp(0.0, 1.0) : 0.0;
    var coord = segStart.interpolateTo(segEnd, fraction);
    final bearing = segStart.bearingTo(segEnd);

    if (includeJitter && jitterMeters > 0) {
      final angle = _random.nextDouble() * 360.0;
      final offset = (_random.nextDouble() - 0.5) * 2.0 * jitterMeters;
      coord = coord.destinationPoint(
        distanceMeters: offset.abs(),
        bearingDegrees: angle,
      );
    }

    final phase = (distanceMeters / 120.0) * math.pi;
    final altitude = baseAltitudeMeters + math.sin(phase) * 4.5;
    final accuracy = math.max(
      1.8,
      baseAccuracyMeters + math.cos(phase * 1.7) * 1.4,
    );
    final speedVariation =
        speedMetersPerSecond * (0.9 + 0.15 * math.sin(phase * 0.8));

    return GeoPosition.fromLatLng(
      latitude: coord.latitude,
      longitude: coord.longitude,
      timestamp: now,
      accuracy: accuracy,
      altitude: altitude,
      altitudeAccuracy: 2.0,
      heading: bearing,
      headingAccuracy: 3.0,
      speed: speedVariation,
      speedAccuracy: 0.4,
      provider: GeoProvider.simulated,
    );
  }

  GeoPosition _nextStepPosition() {
    final stepMeters =
        speedMetersPerSecond * (updateInterval.inMilliseconds / 1000.0);
    if (_tickCount > 0) {
      _distanceTraveledMeters += stepMeters;
    }
    _tickCount++;
    final pos = positionAtDistance(_distanceTraveledMeters);
    _lastPosition = pos;
    return pos;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<GeoPermissionStatus> checkPermission() async => permissionStatus;

  @override
  Future<GeoPermissionStatus> requestPermission({bool always = false}) async {
    if (permissionStatus == GeoPermissionStatus.denied) {
      permissionStatus = always
          ? GeoPermissionStatus.always
          : GeoPermissionStatus.whileInUse;
    }
    return permissionStatus;
  }

  @override
  Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  }) async {
    if (!serviceEnabled) {
      throw const GeoServiceDisabledException();
    }
    if (!permissionStatus.isGranted) {
      throw GeoPermissionDeniedException(
        'Simulated permission denied.',
        status: permissionStatus,
      );
    }
    return _nextStepPosition();
  }

  @override
  Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    return _lastPosition;
  }

  @override
  Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  }) {
    if (!serviceEnabled) {
      return Stream<GeoPosition>.error(const GeoServiceDisabledException());
    }
    if (!permissionStatus.isGranted) {
      return Stream<GeoPosition>.error(
        GeoPermissionDeniedException(
          'Simulated permission denied.',
          status: permissionStatus,
        ),
      );
    }

    final interval =
        settings.timeInterval > Duration.zero &&
            settings.timeInterval < updateInterval
        ? settings.timeInterval
        : updateInterval;

    return Stream<GeoPosition>.multi((
      StreamController<GeoPosition> controller,
    ) {
      Timer? timer;
      controller.add(_nextStepPosition());
      timer = Timer.periodic(interval, (_) {
        if (controller.isClosed) return;
        if (!serviceEnabled) {
          controller.addError(const GeoServiceDisabledException());
          return;
        }
        controller.add(_nextStepPosition());
      });
      controller.onCancel = () async {
        timer?.cancel();
        timer = null;
        await controller.close();
      };
    });
  }

  @override
  Stream<GeoServiceStatus> serviceStatusStream() =>
      _serviceStatusController.stream;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  /// Closes internal broadcast stream controllers.
  Future<void> dispose() async {
    await _serviceStatusController.close();
  }
}
