import 'dart:async';

import 'core/geo_coordinate.dart';
import 'core/geo_position.dart';
import 'core/geo_settings.dart';
import 'engine/geo_kalman_filter.dart';
import 'platform/geolocation_platform.dart';

/// High-level entry point for accessing device geolocation, permissions,
/// continuous filtered streams, and WGS-84 geodetic calculations.
///
/// ```dart
/// final position = await FlutterGeolocation.getCurrentPosition(
///   settings: const GeoSettings(accuracy: GeoAccuracy.best),
/// );
/// ```
abstract final class FlutterGeolocation {
  /// Active underlying [GeolocationPlatform] implementation.
  static GeolocationPlatform get platform => GeolocationPlatform.instance;

  /// Overrides the active [GeolocationPlatform] (useful for tests or
  /// `SimulatedGeolocationPlatform`).
  static set platform(GeolocationPlatform value) {
    GeolocationPlatform.instance = value;
  }

  /// Checks whether device-level location services are currently enabled.
  static Future<bool> isLocationServiceEnabled() =>
      platform.isLocationServiceEnabled();

  /// Checks the current location permission status without prompting the user.
  static Future<GeoPermissionStatus> checkPermission() =>
      platform.checkPermission();

  /// Prompts the user for location permission if needed.
  ///
  /// Set [always] to `true` to request background location permission on
  /// supported platforms.
  static Future<GeoPermissionStatus> requestPermission({bool always = false}) =>
      platform.requestPermission(always: always);

  /// Ensures location permission is granted, requesting it only if currently
  /// [GeoPermissionStatus.denied].
  static Future<GeoPermissionStatus> ensurePermission({
    bool always = false,
  }) async {
    final current = await checkPermission();
    if (current.isGranted) return current;
    if (current == GeoPermissionStatus.deniedForever) return current;
    return requestPermission(always: always);
  }

  /// Fetches a single current [GeoPosition] using [settings].
  static Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  }) => platform.getCurrentPosition(settings: settings);

  /// Returns the most recent cached [GeoPosition] known to the OS, or `null`.
  static Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) =>
      platform.getLastKnownPosition(forceLocationManager: forceLocationManager);

  /// Streams continuous [GeoPosition] updates configured by [settings].
  ///
  /// When [GeoSettings.enableKalmanFilter] is `true`, incoming fixes are
  /// automatically smoothed through a per-subscription [GeoKalmanFilter] and
  /// impossible teleportation spikes are filtered out.
  static Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  }) {
    final source = platform.positionStream(settings: settings);
    if (!settings.enableKalmanFilter) {
      return source;
    }

    return Stream<GeoPosition>.multi((StreamController<GeoPosition> out) {
      final filter = GeoKalmanFilter(
        processNoiseMetersPerSecond: settings.kalmanProcessNoise,
        maxSpeedMetersPerSecond: settings.maxAcceptedSpeedMetersPerSecond,
      );
      final sub = source.listen(
        (GeoPosition raw) {
          final smoothed = filter.process(raw);
          if (smoothed != null) {
            out.add(smoothed);
          }
        },
        onError: out.addError,
        onDone: out.close,
      );
      out.onCancel = sub.cancel;
    });
  }

  /// Streams device-level location service status changes.
  static Stream<GeoServiceStatus> serviceStatusStream() =>
      platform.serviceStatusStream();

  /// Opens the operating system's application settings page.
  static Future<bool> openAppSettings() => platform.openAppSettings();

  /// Opens the operating system's location settings page.
  static Future<bool> openLocationSettings() => platform.openLocationSettings();

  /// Computes the high-precision WGS-84 distance in meters between two
  /// coordinates.
  static double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return GeoCoordinate(
      startLatitude,
      startLongitude,
    ).distanceTo(GeoCoordinate(endLatitude, endLongitude));
  }

  /// Computes the high-precision WGS-84 initial bearing in degrees `[0, 360)`
  /// from start to end coordinates.
  static double bearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return GeoCoordinate(
      startLatitude,
      startLongitude,
    ).bearingTo(GeoCoordinate(endLatitude, endLongitude));
  }
}
