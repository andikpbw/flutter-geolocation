import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import 'geolocation_platform.dart';

/// Default [GeolocationPlatform] implementation backed by Flutter platform
/// channels (`MethodChannel` + `EventChannel`) for Android, iOS, macOS,
/// Windows, and Linux.
class MethodChannelGeolocation extends GeolocationPlatform {
  /// Creates a [MethodChannelGeolocation] with optional custom channels for
  /// testing.
  MethodChannelGeolocation({
    MethodChannel? methodChannel,
    EventChannel? positionChannel,
    EventChannel? serviceStatusChannel,
  }) : methodChannel =
           methodChannel ??
           const MethodChannel('id.humanize.geolocator_flutter/methods'),
       positionChannel =
           positionChannel ??
           const EventChannel('id.humanize.geolocator_flutter/positions'),
       serviceStatusChannel =
           serviceStatusChannel ??
           const EventChannel('id.humanize.geolocator_flutter/service_status');

  /// Primary method channel used for one-shot commands.
  @visibleForTesting
  final MethodChannel methodChannel;

  /// Event channel streaming continuous location fixes.
  @visibleForTesting
  final EventChannel positionChannel;

  /// Event channel streaming OS location-service status changes.
  @visibleForTesting
  final EventChannel serviceStatusChannel;

  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'isLocationServiceEnabled',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const GeoUnsupportedException();
    }
  }

  @override
  Future<GeoPermissionStatus> checkPermission() async {
    try {
      final result = await methodChannel.invokeMethod<String>(
        'checkPermission',
      );
      return GeoPermissionStatus.fromName(result);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const GeoUnsupportedException();
    }
  }

  @override
  Future<GeoPermissionStatus> requestPermission({bool always = false}) async {
    try {
      final result = await methodChannel.invokeMethod<String>(
        'requestPermission',
        <String, Object?>{'always': always},
      );
      return GeoPermissionStatus.fromName(result);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const GeoUnsupportedException();
    }
  }

  @override
  Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  }) async {
    try {
      final future = methodChannel.invokeMapMethod<Object?, Object?>(
        'getCurrentPosition',
        settings.toMap(),
      );
      final raw = settings.timeout != null
          ? await future.timeout(
              settings.timeout!,
              onTimeout: () => throw GeoTimeoutException(
                'Timed out waiting for location fix after '
                '${settings.timeout!.inMilliseconds}ms.',
                timeout: settings.timeout,
              ),
            )
          : await future;
      if (raw == null) {
        throw const GeoUnknownException(
          'Platform returned an empty location payload.',
        );
      }
      final position = GeoPosition.fromMap(raw);
      if (!settings.allowMockLocations && position.isMocked) {
        throw const GeoMockLocationException();
      }
      return position;
    } on GeoException {
      rethrow;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const GeoUnsupportedException();
    }
  }

  @override
  Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    try {
      final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
        'getLastKnownPosition',
        <String, Object?>{'forceLocationManager': forceLocationManager},
      );
      if (raw == null) return null;
      return GeoPosition.fromMap(raw);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const GeoUnsupportedException();
    }
  }

  @override
  Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  }) {
    final rawStream = positionChannel.receiveBroadcastStream(settings.toMap());
    return rawStream.transform(
      StreamTransformer<dynamic, GeoPosition>.fromHandlers(
        handleData: (dynamic data, EventSink<GeoPosition> sink) {
          if (data is Map<Object?, Object?>) {
            final position = GeoPosition.fromMap(data);
            if (!settings.allowMockLocations && position.isMocked) {
              return;
            }
            sink.add(position);
          }
        },
        handleError:
            (Object error, StackTrace stackTrace, EventSink<GeoPosition> sink) {
              if (error is PlatformException) {
                sink.addError(mapPlatformException(error), stackTrace);
              } else if (error is MissingPluginException) {
                sink.addError(const GeoUnsupportedException(), stackTrace);
              } else {
                sink.addError(error, stackTrace);
              }
            },
      ),
    );
  }

  @override
  Stream<GeoServiceStatus> serviceStatusStream() {
    return serviceStatusChannel.receiveBroadcastStream().transform(
      StreamTransformer<dynamic, GeoServiceStatus>.fromHandlers(
        handleData: (dynamic data, EventSink<GeoServiceStatus> sink) {
          sink.add(GeoServiceStatus.fromValue(data));
        },
        handleError:
            (
              Object error,
              StackTrace stackTrace,
              EventSink<GeoServiceStatus> sink,
            ) {
              if (error is PlatformException) {
                sink.addError(mapPlatformException(error), stackTrace);
              } else if (error is MissingPluginException) {
                sink.addError(const GeoUnsupportedException(), stackTrace);
              } else {
                sink.addError(error, stackTrace);
              }
            },
      ),
    );
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('openAppSettings');
      return result ?? false;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'openLocationSettings',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      return false;
    }
  }

  /// Translates a native [PlatformException] into a strongly-typed
  /// [GeoException].
  static GeoException mapPlatformException(PlatformException error) {
    final msg = error.message ?? 'Location operation failed.';
    switch (error.code.toUpperCase()) {
      case 'PERMISSION_DENIED':
        return GeoPermissionDeniedException(msg);
      case 'PERMISSION_DENIED_FOREVER':
        return GeoPermissionDeniedException(
          msg,
          status: GeoPermissionStatus.deniedForever,
        );
      case 'SERVICE_DISABLED':
        return GeoServiceDisabledException(msg);
      case 'TIMEOUT':
        return GeoTimeoutException(msg);
      case 'MOCK_LOCATION_REJECTED':
        return GeoMockLocationException(msg);
      case 'UNSUPPORTED':
        return GeoUnsupportedException(msg);
      default:
        return GeoUnknownException(msg, code: error.code, cause: error);
    }
  }
}
