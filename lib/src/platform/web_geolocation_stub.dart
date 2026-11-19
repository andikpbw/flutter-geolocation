import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import 'geolocation_platform.dart';

/// Non-web stub implementation selected via conditional imports on native VM
/// platforms.
GeolocationPlatform createWebGeolocationPlatform() =>
    const _UnsupportedWebGeolocationPlatform();

class _UnsupportedWebGeolocationPlatform extends GeolocationPlatform {
  const _UnsupportedWebGeolocationPlatform();

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<GeoPermissionStatus> checkPermission() async =>
      GeoPermissionStatus.unableToDetermine;

  @override
  Future<GeoPermissionStatus> requestPermission({bool always = false}) async =>
      GeoPermissionStatus.unableToDetermine;

  @override
  Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  }) {
    return Future<GeoPosition>.error(
      const GeoUnsupportedException(
        'Web geolocation platform is only available in browser environments.',
      ),
    );
  }

  @override
  Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  }) {
    return Stream<GeoPosition>.error(
      const GeoUnsupportedException(
        'Web geolocation platform is only available in browser environments.',
      ),
    );
  }

  @override
  Stream<GeoServiceStatus> serviceStatusStream() =>
      const Stream<GeoServiceStatus>.empty();

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}
