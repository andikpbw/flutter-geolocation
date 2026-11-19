import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator_flutter/geolocator_flutter.dart';

void main() {
  // Use the built-in deterministic simulator for instant cross-platform demo.
  // Remove this line to read directly from device GPS / browser geolocation.
  FlutterGeolocation.platform = SimulatedGeolocationPlatform(
    speedMetersPerSecond: 16.0,
    updateInterval: const Duration(milliseconds: 300),
    baseAccuracyMeters: 3.4,
    jitterMeters: 0.9,
  );
  runApp(const GeolocationExampleApp());
}

/// Complete, zero-Material showcase application built purely on
/// `package:flutter/widgets.dart` (100% compatible with Flutter 3.47–3.50+).
class GeolocationExampleApp extends StatefulWidget {
  /// Creates a [GeolocationExampleApp].
  const GeolocationExampleApp({super.key});

  @override
  State<GeolocationExampleApp> createState() => _GeolocationExampleAppState();
}

class _GeolocationExampleAppState extends State<GeolocationExampleApp> {
  late final GeoController _controller;
  bool _isDark = true;
  bool _kalmanEnabled = true;

  static final List<GeofenceRegion> _demoGeofences = <GeofenceRegion>[
    CircularGeofence(
      id: 'monas-core',
      name: 'Monas Core',
      center: const GeoCoordinate.unchecked(-6.17539, 106.82715),
      radiusMeters: 165.0,
      hysteresisMeters: 12.0,
      dwellDuration: const Duration(seconds: 4),
    ),
    CircularGeofence(
      id: 'merdeka-north',
      name: 'Merdeka Plaza',
      center: const GeoCoordinate.unchecked(-6.17335, 106.82665),
      radiusMeters: 135.0,
      hysteresisMeters: 10.0,
    ),
  ];

  static const List<GeoWaypoint> _demoWaypoints = <GeoWaypoint>[
    GeoWaypoint(
      coordinate: GeoCoordinate.unchecked(-6.17539, 106.82715),
      label: 'MONAS',
      isTarget: true,
    ),
    GeoWaypoint(
      coordinate: GeoCoordinate.unchecked(-6.17360, 106.82860),
      label: 'GAMBIR',
    ),
    GeoWaypoint(
      coordinate: GeoCoordinate.unchecked(-6.17665, 106.82495),
      label: 'THAMRIN',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = GeoController(
      settings: const GeoSettings(
        accuracy: GeoAccuracy.navigation,
        timeInterval: Duration(milliseconds: 300),
        enableKalmanFilter: true,
      ),
      geofences: _demoGeofences,
    );
    unawaited(_controller.startTracking());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleKalman() async {
    setState(() => _kalmanEnabled = !_kalmanEnabled);
    await _controller.updateSettings(
      _controller.settings.copyWith(enableKalmanFilter: _kalmanEnabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isDark ? GeoTheme.dark() : GeoTheme.light();
    return WidgetsApp(
      title: 'Flutter Geolocation Studio',
      color: theme.primaryColor,
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? _) {
        return GeoThemeScope(
          theme: theme,
          child: ColoredBox(
            color: theme.backgroundColor,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (BuildContext context, Widget? _) {
                  return GeolocationDashboardView(
                    position: _controller.position,
                    trail: _controller.trail,
                    geofences: _demoGeofences,
                    activeGeofences: _controller.activeGeofences,
                    recentEvents: _controller.recentGeofenceEvents,
                    waypoints: _demoWaypoints,
                    trackStats: _controller.trackStats,
                    isTracking: _controller.isTracking,
                    kalmanEnabled: _kalmanEnabled,
                    isDark: _isDark,
                    onToggleTracking: () {
                      if (_controller.isTracking) {
                        unawaited(_controller.stopTracking());
                      } else {
                        unawaited(_controller.startTracking());
                      }
                    },
                    onToggleKalman: _toggleKalman,
                    onToggleTheme: () => setState(() => _isDark = !_isDark),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reusable dashboard layout showcasing `GeoRadarWidget`, `GeoCompassWidget`,
/// `GeoTelemetryCard`, and `GeoStatusBadge` in concert.
class GeolocationDashboardView extends StatelessWidget {
  /// Creates a [GeolocationDashboardView].
  const GeolocationDashboardView({
    required this.position,
    required this.trail,
    required this.geofences,
    required this.activeGeofences,
    required this.recentEvents,
    required this.waypoints,
    required this.trackStats,
    required this.isTracking,
    required this.kalmanEnabled,
    required this.isDark,
    super.key,
    this.sweepAngleRadians,
    this.coordinateFormat = GeoCoordinateFormat.decimalDegreesHemisphere,
    this.onToggleTracking,
    this.onToggleKalman,
    this.onToggleTheme,
  });

  /// Active GPS fix.
  final GeoPosition? position;

  /// Breadcrumb trail coordinates.
  final List<GeoCoordinate> trail;

  /// All monitored geofences.
  final List<GeofenceRegion> geofences;

  /// Geofences currently containing [position].
  final List<GeofenceRegion> activeGeofences;

  /// Recent geofence transition events.
  final List<GeofenceEvent> recentEvents;

  /// Waypoints displayed on the radar.
  final List<GeoWaypoint> waypoints;

  /// Live recording metrics.
  final GeoTrackStats trackStats;

  /// Whether streaming is active.
  final bool isTracking;

  /// Whether Kalman smoothing is enabled.
  final bool kalmanEnabled;

  /// Whether dark theme is active.
  final bool isDark;

  /// Optional fixed radar sweep angle for deterministic rendering.
  final double? sweepAngleRadians;

  /// Coordinate format shown on the telemetry card.
  final GeoCoordinateFormat coordinateFormat;

  /// Callback toggling tracking state.
  final VoidCallback? onToggleTracking;

  /// Callback toggling Kalman filtering.
  final VoidCallback? onToggleKalman;

  /// Callback toggling dark/light theme.
  final VoidCallback? onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = GeoTheme.of(context);
    final targetBearing = position != null && waypoints.isNotEmpty
        ? position!.coordinate.bearingTo(waypoints.first.coordinate)
        : null;
    final targetDistance = position != null && waypoints.isNotEmpty
        ? position!.coordinate.distanceTo(waypoints.first.coordinate)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header bar
              Row(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[theme.primaryColor, theme.successColor],
                      ),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: const SizedBox(
                      width: 34.0,
                      height: 34.0,
                      child: Center(
                        child: Text(
                          'GF',
                          style: TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF04111D),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'GEOLOCATOR FLUTTER',
                          style: TextStyle(
                            fontSize: 15.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: theme.textPrimaryColor,
                          ),
                        ),
                        Text(
                          'WGS-84 Telemetry  •  Adaptive Kalman  •  Live Geofencing',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                            color: theme.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PillButton(
                    label: kalmanEnabled ? 'KALMAN ON' : 'KALMAN OFF',
                    active: kalmanEnabled,
                    accent: theme.primaryColor,
                    theme: theme,
                    onTap: onToggleKalman,
                  ),
                  const SizedBox(width: 8.0),
                  _PillButton(
                    label: isTracking ? 'LIVE' : 'PAUSED',
                    active: isTracking,
                    accent: theme.successColor,
                    theme: theme,
                    onTap: onToggleTracking,
                  ),
                  const SizedBox(width: 8.0),
                  _PillButton(
                    label: isDark ? 'DARK' : 'LIGHT',
                    active: false,
                    accent: theme.secondaryColor,
                    theme: theme,
                    onTap: onToggleTheme,
                  ),
                ],
              ),
              const SizedBox(height: 18.0),

              // Main dual-instrument stage: Radar HUD + Compass & Target panel.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final wide = constraints.maxWidth >= 640.0;
                  final radarPanel = DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.surfaceColor,
                      borderRadius: BorderRadius.circular(theme.borderRadius),
                      border: Border.all(color: theme.borderColor, width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                'TACTICAL RADAR HUD',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: theme.textSecondaryColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'RANGE 450m',
                                style: TextStyle(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w700,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12.0),
                          GeoRadarWidget(
                            position: position,
                            trail: trail,
                            geofences: geofences,
                            waypoints: waypoints,
                            rangeMeters: 450.0,
                            size: 256.0,
                            animateSweep: sweepAngleRadians == null,
                            sweepAngleRadians: sweepAngleRadians,
                            theme: theme,
                          ),
                        ],
                      ),
                    ),
                  );

                  final sidePanel = DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.surfaceColor,
                      borderRadius: BorderRadius.circular(theme.borderRadius),
                      border: Border.all(color: theme.borderColor, width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                'PRECISION COMPASS',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: theme.textSecondaryColor,
                                ),
                              ),
                              const Spacer(),
                              if (targetDistance != null)
                                Text(
                                  'MONAS ${GeoMath.formatDistanceMetric(targetDistance)}',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w700,
                                    color: theme.warningColor,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          Center(
                            child: GeoCompassWidget(
                              headingDegrees: position?.heading ?? 0.0,
                              targetBearingDegrees: targetBearing,
                              size: 184.0,
                              animationDuration: sweepAngleRadians != null
                                  ? Duration.zero
                                  : const Duration(milliseconds: 240),
                              theme: theme,
                            ),
                          ),
                          if (wide) const Spacer(),
                          const SizedBox(height: 14.0),
                          _GeofenceEventStrip(
                            events: recentEvents,
                            activeGeofences: activeGeofences,
                            theme: theme,
                          ),
                        ],
                      ),
                    ),
                  );

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: 11, child: radarPanel),
                          const SizedBox(width: 14.0),
                          Expanded(flex: 10, child: sidePanel),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      radarPanel,
                      const SizedBox(height: 14.0),
                      sidePanel,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14.0),

              // Full-width telemetry readout card.
              GeoTelemetryCard(
                key: ValueKey<GeoCoordinateFormat>(coordinateFormat),
                position: position,
                trackStats: trackStats,
                activeGeofences: activeGeofences,
                isTracking: isTracking,
                initialFormat: coordinateFormat,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeofenceEventStrip extends StatelessWidget {
  const _GeofenceEventStrip({
    required this.events,
    required this.activeGeofences,
    required this.theme,
  });

  final List<GeofenceEvent> events;
  final List<GeofenceRegion> activeGeofences;
  final GeoTheme theme;

  @override
  Widget build(BuildContext context) {
    final latest = events.isNotEmpty ? events.last : null;
    final hasActive = activeGeofences.isNotEmpty;
    final accent = hasActive ? theme.successColor : theme.secondaryColor;
    final statusTitle = hasActive
        ? 'ACTIVE ZONE: ${activeGeofences.first.name ?? activeGeofences.first.id}'
        : 'MONITORING 2 GEOFENCES';
    final detail = latest != null
        ? 'Last event: ${latest.transition.name.toUpperCase()} '
              '${latest.region.name ?? latest.region.id}'
        : 'Hysteresis guard & dwell timer armed';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: accent.withValues(alpha: 0.36)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              statusTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: accent,
              ),
            ),
            const SizedBox(height: 3.0),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: theme.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.active,
    required this.accent,
    required this.theme,
    this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final GeoTheme theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.18) : theme.surfaceColor,
          borderRadius: BorderRadius.circular(999.0),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.65) : theme.borderColor,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11.0, vertical: 6.0),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: active ? accent : theme.textSecondaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
