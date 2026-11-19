import 'dart:async';
import 'dart:js_interop';

import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import 'geolocation_platform.dart';

/// Creates the Wasm-ready W3C Geolocation API web platform implementation.
GeolocationPlatform createWebGeolocationPlatform() => WebGeolocationPlatform();

@JS('navigator')
external _JSNavigator? get _navigator;

extension type _JSNavigator._(JSObject _) implements JSObject {
  external _JSGeolocation? get geolocation;
  external _JSPermissions? get permissions;
}

extension type _JSGeolocation._(JSObject _) implements JSObject {
  external void getCurrentPosition(
    JSFunction successCallback, [
    JSFunction? errorCallback,
    _JSPositionOptions? options,
  ]);

  external JSNumber watchPosition(
    JSFunction successCallback, [
    JSFunction? errorCallback,
    _JSPositionOptions? options,
  ]);

  external void clearWatch(JSNumber watchId);
}

extension type _JSPositionOptions._(JSObject _) implements JSObject {
  external factory _JSPositionOptions({
    bool enableHighAccuracy,
    int maximumAge,
  });

  external factory _JSPositionOptions.withTimeout({
    bool enableHighAccuracy,
    int timeout,
    int maximumAge,
  });
}

extension type _JSGeolocationPosition._(JSObject _) implements JSObject {
  external _JSGeolocationCoordinates get coords;
  external JSNumber get timestamp;
}

extension type _JSGeolocationCoordinates._(JSObject _) implements JSObject {
  external JSNumber get latitude;
  external JSNumber get longitude;
  external JSNumber get accuracy;
  external JSNumber? get altitude;
  external JSNumber? get altitudeAccuracy;
  external JSNumber? get heading;
  external JSNumber? get speed;
}

extension type _JSGeolocationPositionError._(JSObject _) implements JSObject {
  external JSNumber get code;
  external JSString get message;
}

extension type _JSPermissions._(JSObject _) implements JSObject {
  external JSPromise<_JSPermissionStatus> query(_JSPermissionDescriptor desc);
}

extension type _JSPermissionDescriptor._(JSObject _) implements JSObject {
  external factory _JSPermissionDescriptor({required JSString name});
}

extension type _JSPermissionStatus._(JSObject _) implements JSObject {
  external JSString get state;
}

/// Wasm-ready browser implementation of [GeolocationPlatform] powered directly
/// by `dart:js_interop` and the W3C Geolocation & Permissions APIs.
class WebGeolocationPlatform extends GeolocationPlatform {
  GeoPosition? _lastKnown;

  _JSGeolocation? get _geo => _navigator?.geolocation;

  @override
  Future<bool> isLocationServiceEnabled() async {
    return _geo != null;
  }

  @override
  Future<GeoPermissionStatus> checkPermission() async {
    final permissions = _navigator?.permissions;
    if (permissions == null) {
      return _geo != null
          ? GeoPermissionStatus.unableToDetermine
          : GeoPermissionStatus.deniedForever;
    }
    try {
      final status = await permissions
          .query(_JSPermissionDescriptor(name: 'geolocation'.toJS))
          .toDart;
      switch (status.state.toDart) {
        case 'granted':
          return GeoPermissionStatus.whileInUse;
        case 'denied':
          return GeoPermissionStatus.deniedForever;
        case 'prompt':
          return GeoPermissionStatus.denied;
        default:
          return GeoPermissionStatus.unableToDetermine;
      }
    } catch (_) {
      return GeoPermissionStatus.unableToDetermine;
    }
  }

  @override
  Future<GeoPermissionStatus> requestPermission({bool always = false}) async {
    final geo = _geo;
    if (geo == null) {
      return GeoPermissionStatus.deniedForever;
    }
    try {
      await getCurrentPosition(
        settings: const GeoSettings(
          accuracy: GeoAccuracy.low,
          timeout: Duration(seconds: 15),
        ),
      );
      return GeoPermissionStatus.whileInUse;
    } on GeoPermissionDeniedException catch (e) {
      return e.status;
    } catch (_) {
      return checkPermission();
    }
  }

  @override
  Future<GeoPosition> getCurrentPosition({
    GeoSettings settings = const GeoSettings(),
  }) {
    final geo = _geo;
    if (geo == null) {
      return Future<GeoPosition>.error(
        const GeoUnsupportedException(
          'Browser navigator.geolocation is unavailable (HTTPS context required).',
        ),
      );
    }

    final completer = Completer<GeoPosition>();
    final onSuccess = ((_JSGeolocationPosition jsPos) {
      if (!completer.isCompleted) {
        final pos = _convertPosition(jsPos);
        _lastKnown = pos;
        completer.complete(pos);
      }
    }).toJS;

    final onError = ((_JSGeolocationPositionError jsErr) {
      if (!completer.isCompleted) {
        completer.completeError(_convertError(jsErr, settings.timeout));
      }
    }).toJS;

    geo.getCurrentPosition(onSuccess, onError, _buildOptions(settings));
    return completer.future;
  }

  @override
  Future<GeoPosition?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    return _lastKnown;
  }

  @override
  Stream<GeoPosition> positionStream({
    GeoSettings settings = const GeoSettings(),
  }) {
    final geo = _geo;
    if (geo == null) {
      return Stream<GeoPosition>.error(
        const GeoUnsupportedException(
          'Browser navigator.geolocation is unavailable.',
        ),
      );
    }

    return Stream<GeoPosition>.multi((
      StreamController<GeoPosition> controller,
    ) {
      JSNumber? watchId;
      GeoPosition? lastEmitted;

      final onSuccess = ((_JSGeolocationPosition jsPos) {
        if (controller.isClosed) return;
        final pos = _convertPosition(jsPos);
        _lastKnown = pos;
        if (lastEmitted != null && settings.distanceFilterMeters > 0) {
          final moved = lastEmitted!.distanceTo(pos);
          if (moved < settings.distanceFilterMeters) return;
        }
        lastEmitted = pos;
        controller.add(pos);
      }).toJS;

      final onError = ((_JSGeolocationPositionError jsErr) {
        if (!controller.isClosed) {
          controller.addError(_convertError(jsErr, settings.timeout));
        }
      }).toJS;

      watchId = geo.watchPosition(onSuccess, onError, _buildOptions(settings));

      controller.onCancel = () async {
        if (watchId != null) {
          geo.clearWatch(watchId!);
          watchId = null;
        }
        await controller.close();
      };
    });
  }

  @override
  Stream<GeoServiceStatus> serviceStatusStream() {
    return Stream<GeoServiceStatus>.value(
      _geo != null ? GeoServiceStatus.enabled : GeoServiceStatus.disabled,
    );
  }

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  static _JSPositionOptions _buildOptions(GeoSettings settings) {
    final highAccuracy =
        settings.accuracy == GeoAccuracy.high ||
        settings.accuracy == GeoAccuracy.best ||
        settings.accuracy == GeoAccuracy.navigation;
    if (settings.timeout != null) {
      return _JSPositionOptions.withTimeout(
        enableHighAccuracy: highAccuracy,
        timeout: settings.timeout!.inMilliseconds,
        maximumAge: 0,
      );
    }
    return _JSPositionOptions(enableHighAccuracy: highAccuracy, maximumAge: 0);
  }

  static GeoPosition _convertPosition(_JSGeolocationPosition jsPos) {
    final coords = jsPos.coords;
    final tsMs = jsPos.timestamp.toDartDouble.round();
    return GeoPosition.fromLatLng(
      latitude: coords.latitude.toDartDouble,
      longitude: coords.longitude.toDartDouble,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true),
      accuracy: coords.accuracy.toDartDouble,
      altitude: coords.altitude.isDefinedAndNotNull
          ? coords.altitude!.toDartDouble
          : 0.0,
      altitudeAccuracy: coords.altitudeAccuracy.isDefinedAndNotNull
          ? coords.altitudeAccuracy!.toDartDouble
          : 0.0,
      heading: coords.heading.isDefinedAndNotNull
          ? coords.heading!.toDartDouble
          : 0.0,
      speed: coords.speed.isDefinedAndNotNull
          ? coords.speed!.toDartDouble
          : 0.0,
      provider: GeoProvider.web,
    );
  }

  static GeoException _convertError(
    _JSGeolocationPositionError error,
    Duration? timeout,
  ) {
    final code = error.code.toDartInt;
    final msg = error.message.toDart;
    switch (code) {
      case 1: // PERMISSION_DENIED
        return GeoPermissionDeniedException(
          msg.isNotEmpty ? msg : 'User denied browser geolocation permission.',
          status: GeoPermissionStatus.deniedForever,
        );
      case 2: // POSITION_UNAVAILABLE
        return GeoServiceDisabledException(
          msg.isNotEmpty ? msg : 'Browser position unavailable.',
        );
      case 3: // TIMEOUT
        return GeoTimeoutException(
          msg.isNotEmpty ? msg : 'Browser geolocation request timed out.',
          timeout: timeout,
        );
      default:
        return GeoUnknownException(
          msg.isNotEmpty ? msg : 'Unknown browser geolocation error.',
          code: 'WEB_$code',
        );
    }
  }
}
