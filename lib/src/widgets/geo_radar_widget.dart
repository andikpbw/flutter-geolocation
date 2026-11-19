import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/geo_coordinate.dart';
import '../core/geo_position.dart';
import '../engine/geofence_engine.dart';
import 'geo_theme.dart';

/// Named geographic marker rendered inside [GeoRadarWidget].
@immutable
class GeoWaypoint {
  /// Creates a [GeoWaypoint].
  const GeoWaypoint({
    required this.coordinate,
    required this.label,
    this.color,
    this.isTarget = false,
  });

  /// WGS-84 coordinate of the waypoint.
  final GeoCoordinate coordinate;

  /// Short label painted beside the marker pin.
  final String label;

  /// Optional custom dot color (defaults to theme warning/secondary color).
  final Color? color;

  /// Highlights this waypoint with a dashed guidance vector from the current
  /// position.
  final bool isTarget;
}

/// Live animated GPS radar HUD displaying current position, accuracy halo,
/// heading cone, breadcrumb trail, circular/polygonal geofences, and waypoints.
///
/// Projects all coordinates into a local East-North-Up (ENU) metric plane
/// centered on [position], ensuring distortion-free circular geofences at any
/// latitude. Built purely on `package:flutter/widgets.dart`.
class GeoRadarWidget extends StatefulWidget {
  /// Creates a [GeoRadarWidget].
  const GeoRadarWidget({
    super.key,
    this.position,
    this.trail = const <GeoCoordinate>[],
    this.geofences = const <GeofenceRegion>[],
    this.waypoints = const <GeoWaypoint>[],
    this.rangeMeters = 450.0,
    this.size = 280.0,
    this.animateSweep = true,
    this.sweepAngleRadians,
    this.headingUp = false,
    this.theme,
  }) : assert(rangeMeters > 0.0, 'rangeMeters must be > 0');

  /// Active GPS fix centered on the radar.
  final GeoPosition? position;

  /// Recent breadcrumb trail coordinates rendered as a fading path.
  final List<GeoCoordinate> trail;

  /// Monitored circular or polygonal geofence regions.
  final List<GeofenceRegion> geofences;

  /// Points of interest or navigation targets plotted on the radar.
  final List<GeoWaypoint> waypoints;

  /// Outer radius represented by the radar dish in meters.
  final double rangeMeters;

  /// Square dimensions of the radar widget in logical pixels.
  final double size;

  /// Enables continuous animated radar sweep when [sweepAngleRadians] is null.
  final bool animateSweep;

  /// Optional deterministic sweep angle in radians (useful for synchronized
  /// animations or golden tests).
  final double? sweepAngleRadians;

  /// When `true`, rotates the radar so the device heading points upward.
  /// Defaults to `false` (North-up).
  final bool headingUp;

  /// Optional theme override; falls back to [GeoTheme.of].
  final GeoTheme? theme;

  @override
  State<GeoRadarWidget> createState() => _GeoRadarWidgetState();
}

class _GeoRadarWidgetState extends State<GeoRadarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animateSweep && widget.sweepAngleRadians == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant GeoRadarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate =
        widget.animateSweep && widget.sweepAngleRadians == null;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.theme ?? GeoTheme.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          final sweep =
              widget.sweepAngleRadians ?? (_controller.value * 2.0 * math.pi);
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _GeoRadarPainter(
              position: widget.position,
              trail: widget.trail,
              geofences: widget.geofences,
              waypoints: widget.waypoints,
              rangeMeters: widget.rangeMeters,
              sweepAngleRadians: sweep,
              showSweep:
                  widget.animateSweep || widget.sweepAngleRadians != null,
              headingUp: widget.headingUp,
              theme: resolved,
            ),
          );
        },
      ),
    );
  }
}

class _GeoRadarPainter extends CustomPainter {
  const _GeoRadarPainter({
    required this.position,
    required this.trail,
    required this.geofences,
    required this.waypoints,
    required this.rangeMeters,
    required this.sweepAngleRadians,
    required this.showSweep,
    required this.headingUp,
    required this.theme,
  });

  final GeoPosition? position;
  final List<GeoCoordinate> trail;
  final List<GeofenceRegion> geofences;
  final List<GeoWaypoint> waypoints;
  final double rangeMeters;
  final double sweepAngleRadians;
  final bool showSweep;
  final bool headingUp;
  final GeoTheme theme;

  static const double _metersPerLatDeg = 111319.49079327358;

  Offset _project(
    GeoCoordinate target,
    GeoCoordinate origin,
    Offset center,
    double radius,
    double rotationRad,
  ) {
    final cosLat = math.max(1e-6, math.cos(GeoMath.toRadians(origin.latitude)));
    var dLon = target.longitude - origin.longitude;
    if (dLon > 180.0) dLon -= 360.0;
    if (dLon < -180.0) dLon += 360.0;

    final eastMeters = dLon * _metersPerLatDeg * cosLat;
    final northMeters = (target.latitude - origin.latitude) * _metersPerLatDeg;
    final scale = radius / rangeMeters;

    var dx = eastMeters * scale;
    var dy = -northMeters * scale;
    if (rotationRad != 0.0) {
      final c = math.cos(rotationRad);
      final s = math.sin(rotationRad);
      final rx = dx * c - dy * s;
      final ry = dx * s + dy * c;
      dx = rx;
      dy = ry;
    }
    return Offset(center.dx + dx, center.dy + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = math.min(size.width, size.height) / 2.0 - 6.0;
    final dishRect = Rect.fromCircle(center: center, radius: radius);

    // Subtle outer ambient glow.
    canvas.drawCircle(
      center,
      radius + 2.0,
      Paint()
        ..color = theme.primaryColor.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8.0),
    );

    // Clip all tactical layers inside the circular dish.
    canvas.save();
    canvas.clipPath(Path()..addOval(dishRect));

    // Radial radar dish fill.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            theme.primaryColor.withValues(alpha: 0.09),
            theme.surfaceColor,
            theme.backgroundColor,
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(dishRect),
    );

    // Concentric range rings & scale captions.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = theme.gridColor.withValues(alpha: 0.7);
    const ringCount = 3;
    for (var i = 1; i <= ringCount; i++) {
      final r = radius * (i / ringCount);
      canvas.drawCircle(center, r, ringPaint);
      final ringMeters = rangeMeters * (i / ringCount);
      final label = GeoMath.formatDistanceMetric(ringMeters, decimals: 1);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
            color: theme.textSecondaryColor.withValues(alpha: 0.72),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + (i == ringCount ? 14.0 : 5.0), center.dy - r + 3.0),
      );
    }

    // Crosshair axes.
    final axisPaint = Paint()
      ..strokeWidth = 0.85
      ..color = theme.gridColor.withValues(alpha: 0.55);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      axisPaint,
    );

    // Animated radar sweep sector.
    if (showSweep) {
      final startAngle = sweepAngleRadians - math.pi / 2.0;
      const sweepSpan = 0.95;
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: sweepSpan,
          colors: <Color>[
            theme.primaryColor.withValues(alpha: 0.0),
            theme.primaryColor.withValues(alpha: 0.24),
          ],
          transform: GradientRotation(startAngle - sweepSpan),
        ).createShader(dishRect);
      canvas.drawArc(
        dishRect,
        startAngle - sweepSpan,
        sweepSpan,
        true,
        sweepPaint,
      );

      // Leading edge beam line.
      final beamEnd = Offset(
        center.dx + math.cos(startAngle) * radius,
        center.dy + math.sin(startAngle) * radius,
      );
      canvas.drawLine(
        center,
        beamEnd,
        Paint()
          ..strokeWidth = 1.6
          ..color = theme.primaryColor.withValues(alpha: 0.7),
      );
    }

    final pos = position;
    if (pos != null) {
      final origin = pos.coordinate;
      final rotationRad = headingUp ? -GeoMath.toRadians(pos.heading) : 0.0;
      final pxPerMeter = radius / rangeMeters;

      // 1. Render geofences (circular & polygonal).
      for (final region in geofences) {
        final isInside = region.contains(origin);
        final color = isInside ? theme.successColor : theme.secondaryColor;
        if (region is CircularGeofence) {
          final cOffset = _project(
            region.center,
            origin,
            center,
            radius,
            rotationRad,
          );
          final rPx = region.radiusMeters * pxPerMeter;
          canvas.drawCircle(
            cOffset,
            rPx,
            Paint()..color = color.withValues(alpha: isInside ? 0.16 : 0.09),
          );
          canvas.drawCircle(
            cOffset,
            rPx,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isInside ? 1.8 : 1.2
              ..color = color.withValues(alpha: isInside ? 0.9 : 0.55),
          );
          _paintSmallTag(
            canvas,
            region.name ?? region.id,
            Offset(cOffset.dx, cOffset.dy - rPx - 10.0),
            color,
          );
        } else if (region is PolygonGeofence) {
          final polyPath = Path();
          for (var i = 0; i < region.polygon.vertices.length; i++) {
            final pt = _project(
              region.polygon.vertices[i],
              origin,
              center,
              radius,
              rotationRad,
            );
            if (i == 0) {
              polyPath.moveTo(pt.dx, pt.dy);
            } else {
              polyPath.lineTo(pt.dx, pt.dy);
            }
          }
          polyPath.close();
          canvas.drawPath(
            polyPath,
            Paint()..color = color.withValues(alpha: isInside ? 0.16 : 0.09),
          );
          canvas.drawPath(
            polyPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isInside ? 1.8 : 1.2
              ..color = color.withValues(alpha: isInside ? 0.9 : 0.55),
          );
        }
      }

      // 2. Render live breadcrumb trail with progressive opacity.
      if (trail.length >= 2) {
        for (var i = 1; i < trail.length; i++) {
          final t = i / (trail.length - 1);
          final p0 = _project(
            trail[i - 1],
            origin,
            center,
            radius,
            rotationRad,
          );
          final p1 = _project(trail[i], origin, center, radius, rotationRad);
          canvas.drawLine(
            p0,
            p1,
            Paint()
              ..strokeWidth = 1.4 + t * 1.8
              ..strokeCap = StrokeCap.round
              ..color = theme.primaryColor.withValues(alpha: 0.14 + t * 0.8),
          );
        }
      }

      // 3. Render waypoints & target guidance vector.
      for (final wp in waypoints) {
        final wpPos = _project(
          wp.coordinate,
          origin,
          center,
          radius,
          rotationRad,
        );
        final wpColor =
            wp.color ??
            (wp.isTarget ? theme.warningColor : theme.secondaryColor);
        if (wp.isTarget) {
          canvas.drawLine(
            center,
            wpPos,
            Paint()
              ..strokeWidth = 1.25
              ..color = wpColor.withValues(alpha: 0.55),
          );
        }
        canvas.drawCircle(
          wpPos,
          6.5,
          Paint()..color = wpColor.withValues(alpha: 0.24),
        );
        canvas.drawCircle(wpPos, 3.4, Paint()..color = wpColor);
        _paintSmallTag(
          canvas,
          wp.label,
          Offset(wpPos.dx, wpPos.dy + 11.0),
          wpColor,
        );
      }

      // 4. Horizontal accuracy halo around the center fix.
      final accuracyPx = (pos.accuracy * pxPerMeter).clamp(10.0, radius * 0.45);
      canvas.drawCircle(
        center,
        accuracyPx,
        Paint()..color = theme.primaryColor.withValues(alpha: 0.14),
      );
      canvas.drawCircle(
        center,
        accuracyPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = theme.primaryColor.withValues(alpha: 0.45),
      );

      // 5. Directional heading cone.
      final headingAngle = headingUp
          ? -math.pi / 2.0
          : GeoMath.toRadians(pos.heading - 90.0);
      const coneSpan = 0.62;
      final coneRect = Rect.fromCircle(center: center, radius: 34.0);
      canvas.drawArc(
        coneRect,
        headingAngle - coneSpan / 2.0,
        coneSpan,
        true,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              theme.primaryColor.withValues(alpha: 0.55),
              theme.primaryColor.withValues(alpha: 0.0),
            ],
          ).createShader(coneRect),
      );

      // 6. Center live GPS lock reticle.
      final pulse = 0.5 + 0.5 * math.sin(sweepAngleRadians * 2.0);
      canvas.drawCircle(
        center,
        9.0 + pulse * 5.0,
        Paint()
          ..color = theme.successColor.withValues(alpha: 0.28 * (1.0 - pulse)),
      );
      canvas.drawCircle(center, 6.2, Paint()..color = theme.textPrimaryColor);
      canvas.drawCircle(center, 4.2, Paint()..color = theme.successColor);
    }

    canvas.restore();

    // Crisp outer rim stroke.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = theme.primaryColor.withValues(alpha: 0.45),
    );

    // Subtle North indicator pill on outer rim.
    final northAngle = headingUp && pos != null
        ? -GeoMath.toRadians(pos.heading) - math.pi / 2.0
        : -math.pi / 2.0;
    final northPos = Offset(
      center.dx + math.cos(northAngle) * (radius - 10.0),
      center.dy + math.sin(northAngle) * (radius - 10.0),
    );
    final nTp = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 10.0,
          fontWeight: FontWeight.w800,
          color: theme.dangerColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    nTp.paint(
      canvas,
      Offset(northPos.dx - nTp.width / 2.0, northPos.dy - nTp.height / 2.0),
    );
  }

  void _paintSmallTag(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 9.0,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: tp.width + 8.0,
        height: tp.height + 3.0,
      ),
      const Radius.circular(4.0),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = theme.backgroundColor.withValues(alpha: 0.82),
    );
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0),
    );
  }

  @override
  bool shouldRepaint(covariant _GeoRadarPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.trail != trail ||
        oldDelegate.geofences != geofences ||
        oldDelegate.waypoints != waypoints ||
        oldDelegate.rangeMeters != rangeMeters ||
        oldDelegate.sweepAngleRadians != sweepAngleRadians ||
        oldDelegate.headingUp != headingUp ||
        oldDelegate.theme != theme;
  }
}
