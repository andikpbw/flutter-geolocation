import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/geo_coordinate.dart';
import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import '../flutter_geolocation_client.dart';
import 'geo_track_recorder.dart';
import 'geofence_engine.dart';

/// Reactive controller managing live location tracking, breadcrumb history,
/// permission state, geofence monitoring, and track recording statistics.
///
/// Built on [ChangeNotifier] with zero external state-management dependencies.
class GeoController extends ChangeNotifier {
  /// Creates a [GeoController].
  GeoController({
    GeoSettings settings = const GeoSettings(),
    this.maxTrailLength = 200,
    Iterable<GeofenceRegion> geofences = const <GeofenceRegion>[],
    bool recordTrack = true,
  }) : _settings = settings,
       _recordTrack = recordTrack,
       geofenceEngine = GeofenceEngine(regions: geofences),
       trackRecorder = GeoTrackRecorder();

  /// Maximum number of recent trail coordinates retained in [trail].
  final int maxTrailLength;

  /// Geofencing engine automatically fed by every incoming fix.
  final GeofenceEngine geofenceEngine;

  /// Track recorder tracking distance, speed, and elevation metrics.
  final GeoTrackRecorder trackRecorder;

  final Queue<GeoCoordinate> _trail = Queue<GeoCoordinate>();
  final List<GeofenceEvent> _recentGeofenceEvents = <GeofenceEvent>[];

  GeoSettings _settings;
  final bool _recordTrack;
  StreamSubscription<GeoPosition>? _positionSub;
  StreamSubscription<GeoServiceStatus>? _serviceSub;

  GeoPosition? _position;
  GeoPermissionStatus _permissionStatus = GeoPermissionStatus.unableToDetermine;
  GeoServiceStatus _serviceStatus = GeoServiceStatus.enabled;
  GeoException? _error;
  bool _isLoading = false;
  bool _isTracking = false;
  bool _disposed = false;

  /// Active tracking configuration.
  GeoSettings get settings => _settings;

  /// Most recent position fix, or `null` before the first lock.
  GeoPosition? get position => _position;

  /// Current permission authorization status.
  GeoPermissionStatus get permissionStatus => _permissionStatus;

  /// Current device location service status.
  GeoServiceStatus get serviceStatus => _serviceStatus;

  /// Last encountered [GeoException], or `null` when healthy.
  GeoException? get error => _error;

  /// Whether an async permission check or initial fix request is in flight.
  bool get isLoading => _isLoading;

  /// Whether continuous location streaming is currently active.
  bool get isTracking => _isTracking;

  /// Ordered breadcrumb trail of recent coordinates (oldest -> newest).
  List<GeoCoordinate> get trail => List<GeoCoordinate>.unmodifiable(_trail);

  /// Most recent geofence events (newest last, capped at 25 entries).
  List<GeofenceEvent> get recentGeofenceEvents =>
      List<GeofenceEvent>.unmodifiable(_recentGeofenceEvents);

  /// Regions the device is currently inside.
  List<GeofenceRegion> get activeGeofences => geofenceEngine.activeRegions;

  /// Live track statistics snapshot.
  GeoTrackStats get trackStats => trackRecorder.stats;

  /// Updates [settings]. If currently tracking, restarts the stream with the
  /// new configuration.
  Future<void> updateSettings(GeoSettings newSettings) async {
    _settings = newSettings;
    if (_isTracking) {
      await stopTracking();
      await startTracking(requestPermissionIfNeeded: false);
    } else {
      _notify();
    }
  }

  /// Fetches a single immediate position fix and updates controller state.
  Future<GeoPosition?> refreshPosition({
    bool requestPermissionIfNeeded = true,
  }) async {
    if (_disposed) return null;
    _isLoading = true;
    _error = null;
    _notify();

    try {
      final enabled = await FlutterGeolocation.isLocationServiceEnabled();
      _serviceStatus = enabled
          ? GeoServiceStatus.enabled
          : GeoServiceStatus.disabled;
      if (!enabled) {
        throw const GeoServiceDisabledException();
      }

      _permissionStatus = requestPermissionIfNeeded
          ? await FlutterGeolocation.ensurePermission()
          : await FlutterGeolocation.checkPermission();
      if (!_permissionStatus.isGranted) {
        throw GeoPermissionDeniedException(
          'Location permission not granted.',
          status: _permissionStatus,
        );
      }

      final fix = await FlutterGeolocation.getCurrentPosition(
        settings: _settings,
      );
      _ingestPosition(fix);
      return fix;
    } on GeoException catch (e) {
      _error = e;
      return null;
    } catch (e) {
      _error = GeoUnknownException(e.toString(), cause: e);
      return null;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Starts continuous location tracking.
  Future<void> startTracking({bool requestPermissionIfNeeded = true}) async {
    if (_disposed || _isTracking) return;
    _isLoading = true;
    _error = null;
    _notify();

    try {
      final enabled = await FlutterGeolocation.isLocationServiceEnabled();
      _serviceStatus = enabled
          ? GeoServiceStatus.enabled
          : GeoServiceStatus.disabled;
      if (!enabled) {
        throw const GeoServiceDisabledException();
      }

      _permissionStatus = requestPermissionIfNeeded
          ? await FlutterGeolocation.ensurePermission()
          : await FlutterGeolocation.checkPermission();
      if (!_permissionStatus.isGranted) {
        throw GeoPermissionDeniedException(
          'Location permission not granted.',
          status: _permissionStatus,
        );
      }

      if (_recordTrack && trackRecorder.state == GeoTrackState.idle) {
        trackRecorder.start();
      } else if (_recordTrack && trackRecorder.state == GeoTrackState.paused) {
        trackRecorder.resume();
      }

      _serviceSub ??= FlutterGeolocation.serviceStatusStream().listen((
        GeoServiceStatus status,
      ) {
        _serviceStatus = status;
        if (status == GeoServiceStatus.disabled) {
          _error = const GeoServiceDisabledException();
        } else if (_error is GeoServiceDisabledException) {
          _error = null;
        }
        _notify();
      }, onError: (_) {});

      _positionSub = FlutterGeolocation.positionStream(settings: _settings)
          .listen(
            (GeoPosition pos) {
              _isLoading = false;
              _error = null;
              _ingestPosition(pos);
              _notify();
            },
            onError: (Object err) {
              _isLoading = false;
              _error = err is GeoException
                  ? err
                  : GeoUnknownException(err.toString(), cause: err);
              _notify();
            },
          );
      _isTracking = true;
    } on GeoException catch (e) {
      _error = e;
      _isLoading = false;
    } catch (e) {
      _error = GeoUnknownException(e.toString(), cause: e);
      _isLoading = false;
    }
    _notify();
  }

  /// Pauses continuous location tracking while preserving history & stats.
  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    if (_recordTrack && trackRecorder.state == GeoTrackState.recording) {
      trackRecorder.pause();
    }
    _isTracking = false;
    _isLoading = false;
    _notify();
  }

  /// Manually injects a [GeoPosition] into the controller (useful for tests,
  /// replaying logs, or driving showcase previews).
  void pushPosition(GeoPosition position) {
    _error = null;
    _ingestPosition(position);
    _notify();
  }

  /// Clears breadcrumb trail, geofence event history, and track recorder.
  void clearHistory() {
    _trail.clear();
    _recentGeofenceEvents.clear();
    trackRecorder.reset();
    if (_isTracking && _recordTrack) {
      trackRecorder.start();
    }
    _notify();
  }

  void _ingestPosition(GeoPosition pos) {
    _position = pos;
    _trail.addLast(pos.coordinate);
    while (_trail.length > maxTrailLength) {
      _trail.removeFirst();
    }
    if (_recordTrack) {
      if (trackRecorder.state == GeoTrackState.idle) {
        trackRecorder.start();
      }
      trackRecorder.record(pos);
    }
    final events = geofenceEngine.processPosition(pos);
    if (events.isNotEmpty) {
      _recentGeofenceEvents.addAll(events);
      if (_recentGeofenceEvents.length > 25) {
        _recentGeofenceEvents.removeRange(0, _recentGeofenceEvents.length - 25);
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_positionSub?.cancel());
    unawaited(_serviceSub?.cancel());
    unawaited(geofenceEngine.dispose());
    super.dispose();
  }
}
