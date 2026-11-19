import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import 'method_channel_geolocation.dart';

/// Platform interface for `flutter_geolocation`.
///
/// Platform-specific implementations (Android, iOS, macOS, Windows, Linux, Web)
/// extend this class and register themselves by setting
/// [GeolocationPlatform.instance]. Tests and offline demos can also swap in
/// `SimulatedGeolocationPlatform` or a custom mock.
abstract class GeolocationPlatform {
  /// Constructs a [GeolocationPlatform].
  const GeolocationPlatform();

  /// The active [GeolocationPlatform] implementation used by
  /// `FlutterGeolocation`.
  static GeolocationPlatform instance = MethodChannelGeolocation();

  /// Checks whether device-level location services are currently enabled.
  Future<bool> isLocationServiceEnabled();

  /// Returns the current location permission status without prompting the user.
  Future<GeoPermissionStatus> checkPermission();

  /// Requests location permission from the user.
  ///
  /// Set [always] to `true` to request background ("Always") authorization on
  /// platforms that distinguish between foreground and background access.
  Future<GeoPermissionStatus> requestPermission({bool always = false});

  /// Fetches a single current position fix using [settings].
  Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  });

  /// Returns the most recent cached position known to the OS, or `null` if
  /// none is available.
  Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  });

  /// Subscribes to continuous position updates configured by [settings].
  Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  });

  /// Subscribes to device location service status changes (enabled / disabled).
  Stream<GeoServiceStatus> serviceStatusStream();

  /// Opens the operating system's application settings page.
  Future<bool> openAppSettings();

  /// Opens the operating system's location settings page.
  Future<bool> openLocationSettings();
}
