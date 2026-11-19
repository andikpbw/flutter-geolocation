/// Modern, lightweight, accurate Flutter geolocation library with zero
/// third-party dependencies.
///
/// Features:
/// - Cross-platform location services (Android, iOS, macOS, Windows, Linux,
///   and WebAssembly-ready Web via `dart:js_interop`).
/// - Survey-grade WGS-84 geodesy (Vincenty inverse & direct formulas,
///   Haversine, SLERP midpoint/interpolation, cross-track/along-track distance,
///   Geohash, DD/DDM/DMS formatting & parsing).
/// - Spatial geometry (`GeoBounds`, `GeoPolyline`, `GeoPolygon`).
/// - Adaptive 2D Kalman GPS smoothing (`GeoKalmanFilter`).
/// - Circular & polygonal geofencing (`GeofenceEngine`) with hysteresis & dwell.
/// - Track recording with statistics, GeoJSON & GPX export (`GeoTrackRecorder`).
/// - Style-agnostic HUD widgets built purely on `package:flutter/widgets.dart`
///   (`GeoRadarWidget`, `GeoCompassWidget`, `GeoTelemetryCard`,
///   `GeoStatusBadge`, `GeoLocationBuilder`, `GeoTheme`).
library;

export 'src/core/geo_bounds.dart';
export 'src/core/geo_coordinate.dart';
export 'src/core/geo_exception.dart';
export 'src/core/geo_geometry.dart';
export 'src/core/geo_position.dart';
export 'src/core/geo_settings.dart';
export 'src/engine/geo_controller.dart';
export 'src/engine/geo_kalman_filter.dart';
export 'src/engine/geo_track_recorder.dart';
export 'src/engine/geofence_engine.dart';
export 'src/flutter_geolocation_client.dart';
export 'src/platform/geolocation_platform.dart';
export 'src/platform/method_channel_geolocation.dart';
export 'src/platform/simulated_geolocation_platform.dart';
export 'src/widgets/geo_compass_widget.dart';
export 'src/widgets/geo_location_builder.dart';
export 'src/widgets/geo_radar_widget.dart';
export 'src/widgets/geo_status_badge.dart';
export 'src/widgets/geo_telemetry_card.dart';
export 'src/widgets/geo_theme.dart';
