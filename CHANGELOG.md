## 1.0.0

* Initial release of `geolocator_flutter` — modern, lightweight, accurate geolocation toolkit with zero third-party dependencies.
* **Cross-Platform Location Engine**: Native implementations for Android, iOS, macOS, Windows, Linux, and WebAssembly-ready Web (`dart:js_interop`).
* **WGS-84 Geodesy Engine**: Sub-millimeter Vincenty inverse & direct formulas (with antipodal fallback), fast Haversine distance, midpoint/SLERP interpolation, cross-track/along-track distance, Geohash encoder/decoder with neighbors, and DD/DDM/DMS coordinate formatting & parsing.
* **Spatial Geometry**: Antimeridian-safe `GeoBounds`, `GeoPolyline` (length, Douglas-Peucker simplification, nearest point, off-route detection), and `GeoPolygon` (ray-casting point-in-polygon, spherical-excess geodesic area).
* **Adaptive 2D Kalman Filter**: Velocity-aware GPS smoothing (`GeoKalmanFilter`) with dynamic accuracy weighting and impossible-jump outlier rejection.
* **Geofencing Engine**: Circular and polygonal geofences (`GeofenceEngine`) supporting `enter`, `exit`, and `dwell` transitions with configurable hysteresis to prevent boundary flapping.
* **Track Recording & Export**: `GeoTrackRecorder` with real-time moving statistics, elevation gain/loss, GeoJSON, and GPX export.
* **Zero-Material Flutter UI Widgets**: Style-agnostic widgets built purely on `package:flutter/widgets.dart` (100% compatible with Flutter 3.47–3.50+): `GeoRadarWidget`, `GeoCompassWidget`, `GeoTelemetryCard`, `GeoStatusBadge`, `GeoLocationBuilder`, and `GeoTheme`.
* **Built-in Simulation Engine**: `SimulatedGeolocationPlatform` for deterministic testing, offline previews, and route replay.
