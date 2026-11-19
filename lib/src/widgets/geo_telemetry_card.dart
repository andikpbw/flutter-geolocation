import 'package:flutter/widgets.dart';

import '../core/geo_coordinate.dart';
import '../core/geo_position.dart';
import '../engine/geo_track_recorder.dart';
import '../engine/geofence_engine.dart';
import 'geo_status_badge.dart';
import 'geo_theme.dart';

/// Detailed, sleek telemetry HUD card presenting live coordinates (with tap to
/// cycle `DD` / `DMS` / `DDM` / `Geohash`), speed, altitude, heading, track
/// distance, and active geofence badges.
///
/// Built purely on `package:flutter/widgets.dart`.
class GeoTelemetryCard extends StatefulWidget {
  /// Creates a [GeoTelemetryCard].
  const GeoTelemetryCard({
    super.key,
    this.position,
    this.trackStats,
    this.activeGeofences = const <GeofenceRegion>[],
    this.isTracking = false,
    this.initialFormat = GeoCoordinateFormat.decimalDegreesHemisphere,
    this.useImperialUnits = false,
    this.onCoordinateTap,
    this.theme,
  });

  /// Active GPS fix, or `null` while acquiring a signal.
  final GeoPosition? position;

  /// Optional live track statistics from `GeoTrackRecorder`.
  final GeoTrackStats? trackStats;

  /// Regions the device is currently inside.
  final List<GeofenceRegion> activeGeofences;

  /// Whether live tracking is active.
  final bool isTracking;

  /// Initial coordinate display format.
  final GeoCoordinateFormat initialFormat;

  /// When `true`, displays speed in `mph` and distances in `ft`/`mi`.
  final bool useImperialUnits;

  /// Optional callback invoked when the formatted coordinate strip is tapped.
  final ValueChanged<String>? onCoordinateTap;

  /// Optional theme override; falls back to [GeoTheme.of].
  final GeoTheme? theme;

  @override
  State<GeoTelemetryCard> createState() => _GeoTelemetryCardState();
}

class _GeoTelemetryCardState extends State<GeoTelemetryCard> {
  static const List<GeoCoordinateFormat> _cycleOrder = <GeoCoordinateFormat>[
    GeoCoordinateFormat.decimalDegreesHemisphere,
    GeoCoordinateFormat.degreesMinutesSeconds,
    GeoCoordinateFormat.degreesDecimalMinutes,
    GeoCoordinateFormat.geohash,
  ];

  late GeoCoordinateFormat _format;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
  }

  void _cycleFormat() {
    final idx = _cycleOrder.indexOf(_format);
    setState(() {
      _format = _cycleOrder[(idx + 1) % _cycleOrder.length];
    });
  }

  String _formatShortName(GeoCoordinateFormat format) {
    switch (format) {
      case GeoCoordinateFormat.decimalDegrees:
      case GeoCoordinateFormat.decimalDegreesHemisphere:
        return 'DD';
      case GeoCoordinateFormat.degreesDecimalMinutes:
        return 'DDM';
      case GeoCoordinateFormat.degreesMinutesSeconds:
        return 'DMS';
      case GeoCoordinateFormat.geohash:
        return 'GEOHASH';
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.theme ?? GeoTheme.of(context);
    final pos = widget.position;
    final formattedCoord = pos != null
        ? pos.coordinate.format(_format)
        : 'Waiting for satellite lock...';

    final speedValue = pos == null
        ? '--'
        : (widget.useImperialUnits
              ? '${pos.speedMph.toStringAsFixed(1)} mph'
              : '${pos.speedKmh.toStringAsFixed(1)} km/h');

    final altValue = pos == null
        ? '--'
        : (widget.useImperialUnits
              ? '${(pos.altitude * 3.28084).toStringAsFixed(0)} ft'
              : '${pos.altitude.toStringAsFixed(1)} m');

    final headingValue = pos == null
        ? '--'
        : '${pos.heading.round().toString().padLeft(3, '0')}° '
              '${pos.compassDirection.abbreviation}';

    final distanceMeters = widget.trackStats?.totalDistanceMeters ?? 0.0;
    final distanceValue = widget.useImperialUnits
        ? GeoMath.formatDistanceImperial(distanceMeters)
        : GeoMath.formatDistanceMetric(distanceMeters);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolved.surfaceColor,
        borderRadius: BorderRadius.circular(resolved.borderRadius),
        border: Border.all(color: resolved.borderColor, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.22),
            blurRadius: 18.0,
            offset: const Offset(0.0, 8.0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Top bar: GPS lock status + provider + format cycle button.
            Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 6.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      GeoStatusBadge(
                        position: pos,
                        isTracking: widget.isTracking,
                        theme: resolved,
                      ),
                      if (pos != null)
                        _SmallChip(
                          label: pos.provider.name.toUpperCase(),
                          color: resolved.secondaryColor,
                          theme: resolved,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                GestureDetector(
                  onTap: _cycleFormat,
                  behavior: HitTestBehavior.opaque,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: resolved.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: resolved.primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9.0,
                        vertical: 5.0,
                      ),
                      child: Text(
                        _formatShortName(_format),
                        style: TextStyle(
                          fontFamily: resolved.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: resolved.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),

            // Coordinate readout banner.
            GestureDetector(
              onTap: () {
                if (widget.onCoordinateTap != null && pos != null) {
                  widget.onCoordinateTap!(formattedCoord);
                } else {
                  _cycleFormat();
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: resolved.backgroundColor.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: resolved.gridColor.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            'WGS-84 COORDINATES',
                            style: TextStyle(
                              fontFamily: resolved.fontFamily,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                              color: resolved.textSecondaryColor,
                            ),
                          ),
                          const Spacer(),
                          if (pos != null)
                            Text(
                              'GH: ${pos.coordinate.toGeohash(precision: 7)}',
                              style: TextStyle(
                                fontFamily: resolved.fontFamily,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: resolved.primaryColor.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        formattedCoord,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: resolved.fontFamily,
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: resolved.textPrimaryColor,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12.0),

            // 4-tile telemetry metric row.
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricTile(
                    label: 'SPEED',
                    value: speedValue,
                    accent: resolved.primaryColor,
                    theme: resolved,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: _MetricTile(
                    label: 'ALTITUDE',
                    value: altValue,
                    accent: resolved.secondaryColor,
                    theme: resolved,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: _MetricTile(
                    label: 'HEADING',
                    value: headingValue,
                    accent: resolved.warningColor,
                    theme: resolved,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: _MetricTile(
                    label: 'DISTANCE',
                    value: distanceValue,
                    accent: resolved.successColor,
                    theme: resolved,
                  ),
                ),
              ],
            ),

            // Active geofence badges.
            if (widget.activeGeofences.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 6.0,
                runSpacing: 6.0,
                children: widget.activeGeofences
                    .map((GeofenceRegion region) {
                      return _SmallChip(
                        label: 'INSIDE • ${region.name ?? region.id}',
                        color: resolved.successColor,
                        theme: resolved,
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.theme,
  });

  final String label;
  final String value;
  final Color accent;
  final GeoTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(11.0),
        border: Border.all(color: theme.gridColor.withValues(alpha: 0.48)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 4.5,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5.0),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: theme.fontFamily,
                      fontSize: 9.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: theme.textSecondaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: theme.textPrimaryColor,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.color,
    required this.theme,
  });

  final String label;
  final Color color;
  final GeoTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 4.0),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 10.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: color,
          ),
        ),
      ),
    );
  }
}
