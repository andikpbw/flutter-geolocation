import 'geo_settings.dart';

/// Base sealed exception type for all geolocation failures.
sealed class GeoException implements Exception {
  /// Creates a [GeoException] with a descriptive [message] and error [code].
  const GeoException(this.message, {required this.code});

  /// Human-readable description of the error.
  final String message;

  /// Machine-readable error code.
  final String code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Thrown when location permission is denied by the user or restricted by OS
/// policy.
final class GeoPermissionDeniedException extends GeoException {
  /// Creates a [GeoPermissionDeniedException].
  const GeoPermissionDeniedException(
    super.message, {
    this.status = GeoPermissionStatus.denied,
  }) : super(code: 'PERMISSION_DENIED');

  /// Underlying permission status that triggered the failure.
  final GeoPermissionStatus status;

  /// Whether the user must open OS settings to grant permission.
  bool get isPermanent => status == GeoPermissionStatus.deniedForever;
}

/// Thrown when the device's system-wide location services are turned off.
final class GeoServiceDisabledException extends GeoException {
  /// Creates a [GeoServiceDisabledException].
  const GeoServiceDisabledException([
    super.message = 'Location services are disabled on this device.',
  ]) : super(code: 'SERVICE_DISABLED');
}

/// Thrown when a location fix could not be obtained within the configured
/// timeout duration.
final class GeoTimeoutException extends GeoException {
  /// Creates a [GeoTimeoutException].
  const GeoTimeoutException(super.message, {this.timeout})
    : super(code: 'TIMEOUT');

  /// The timeout duration that was exceeded, if known.
  final Duration? timeout;
}

/// Thrown when a mocked/spoofed position is received while
/// `GeoSettings.allowMockLocations` is `false`.
final class GeoMockLocationException extends GeoException {
  /// Creates a [GeoMockLocationException].
  const GeoMockLocationException([
    super.message = 'Mocked location fixes are disallowed by GeoSettings.',
  ]) : super(code: 'MOCK_LOCATION_REJECTED');
}

/// Thrown when the current platform or browser does not support a requested
/// geolocation feature.
final class GeoUnsupportedException extends GeoException {
  /// Creates a [GeoUnsupportedException].
  const GeoUnsupportedException([
    super.message = 'Geolocation is not supported on this platform.',
  ]) : super(code: 'UNSUPPORTED');
}

/// Thrown when an unexpected platform or sensor error occurs.
final class GeoUnknownException extends GeoException {
  /// Creates a [GeoUnknownException].
  const GeoUnknownException(
    super.message, {
    super.code = 'UNKNOWN',
    this.cause,
  });

  /// Optional original error object from the underlying platform.
  final Object? cause;
}
