import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/geo_coordinate.dart';
import 'geo_theme.dart';

/// High-precision animated 360° compass instrument dial built purely with
/// `package:flutter/widgets.dart`.
///
/// Uses continuous shortest-path angular interpolation so crossing `359° -> 0°`
/// rotates smoothly without wrapping backward.
class GeoCompassWidget extends StatefulWidget {
  /// Creates a [GeoCompassWidget].
  const GeoCompassWidget({
    required this.headingDegrees,
    super.key,
    this.targetBearingDegrees,
    this.size = 180.0,
    this.animationDuration = const Duration(milliseconds: 280),
    this.showDigitalReadout = true,
    this.theme,
  });

  /// Current heading in degrees clockwise from true north `[0, 360)`.
  final double headingDegrees;

  /// Optional bearing to a destination waypoint shown as an amber marker on
  /// the compass bezel.
  final double? targetBearingDegrees;

  /// Diameter of the circular compass widget in logical pixels.
  final double size;

  /// Duration for smooth heading transitions. Set to [Duration.zero] for
  /// instantaneous updates.
  final Duration animationDuration;

  /// Whether to display the center digital degree and cardinal readout.
  final bool showDigitalReadout;

  /// Optional theme override; falls back to [GeoTheme.of].
  final GeoTheme? theme;

  @override
  State<GeoCompassWidget> createState() => _GeoCompassWidgetState();
}

class _GeoCompassWidgetState extends State<GeoCompassWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _fromAngle;
  late double _toAngle;
  late double _currentAngle;

  @override
  void initState() {
    super.initState();
    _fromAngle = GeoMath.normalizeBearing(widget.headingDegrees);
    _toAngle = _fromAngle;
    _currentAngle = _fromAngle;
    _controller =
        AnimationController(vsync: this, duration: widget.animationDuration)
          ..addListener(() {
            final t = Curves.easeOutCubic.transform(_controller.value);
            setState(() {
              _currentAngle = _fromAngle + (_toAngle - _fromAngle) * t;
            });
          });
  }

  @override
  void didUpdateWidget(covariant GeoCompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationDuration != widget.animationDuration) {
      _controller.duration = widget.animationDuration;
    }
    if (oldWidget.headingDegrees != widget.headingDegrees) {
      final target = GeoMath.normalizeBearing(widget.headingDegrees);
      final delta = GeoMath.shortestAngleDelta(_currentAngle, target);
      _fromAngle = _currentAngle;
      _toAngle = _currentAngle + delta;
      if (widget.animationDuration == Duration.zero) {
        _currentAngle = _toAngle;
      } else {
        _controller.forward(from: 0.0);
      }
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
    final normalized = GeoMath.normalizeBearing(_currentAngle);
    final cardinal = CompassDirection.fromBearing(normalized);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(widget.size),
            painter: _GeoCompassPainter(
              headingDegrees: normalized,
              targetBearingDegrees: widget.targetBearingDegrees,
              theme: resolved,
            ),
          ),
          if (widget.showDigitalReadout)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${normalized.round().toString().padLeft(3, '0')}°',
                  style: TextStyle(
                    fontFamily: resolved.fontFamily,
                    fontSize: widget.size * 0.165,
                    fontWeight: FontWeight.w800,
                    color: resolved.textPrimaryColor,
                    height: 1.0,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 3.0),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: resolved.primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999.0),
                    border: Border.all(
                      color: resolved.primaryColor.withValues(alpha: 0.4),
                      width: 0.9,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.0,
                    ),
                    child: Text(
                      cardinal.abbreviation,
                      style: TextStyle(
                        fontFamily: resolved.fontFamily,
                        fontSize: math.max(9.5, widget.size * 0.062),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: resolved.primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GeoCompassPainter extends CustomPainter {
  const _GeoCompassPainter({
    required this.headingDegrees,
    required this.targetBearingDegrees,
    required this.theme,
  });

  final double headingDegrees;
  final double? targetBearingDegrees;
  final GeoTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = math.min(size.width, size.height) / 2.0 - 4.0;

    // Outer metallic dial surface.
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[theme.surfaceColor, theme.backgroundColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Outer bezel stroke.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = theme.borderColor,
    );

    // Subtle inner concentric ring.
    canvas.drawCircle(
      center,
      radius * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = theme.gridColor.withValues(alpha: 0.55),
    );

    // Fixed lubber line at 12 o'clock showing current heading reference.
    final lubberPath = Path()
      ..moveTo(center.dx, center.dy - radius - 1.5)
      ..lineTo(center.dx - 5.0, center.dy - radius + 6.5)
      ..lineTo(center.dx + 5.0, center.dy - radius + 6.5)
      ..close();
    canvas.drawPath(lubberPath, Paint()..color = theme.primaryColor);

    // Rotate compass rose counter-clockwise by headingDegrees so the active
    // heading aligns cleanly with the top lubber marker.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-GeoMath.toRadians(headingDegrees));

    // Degree tick marks every 5°.
    for (var deg = 0; deg < 360; deg += 5) {
      final isCardinal = deg % 90 == 0;
      final isMajor = deg % 30 == 0;
      final isMedium = deg % 10 == 0;
      final tickLen = isCardinal
          ? radius * 0.14
          : (isMajor
                ? radius * 0.11
                : (isMedium ? radius * 0.07 : radius * 0.04));
      final angleRad = GeoMath.toRadians(deg - 90.0);
      final outer = Offset(
        math.cos(angleRad) * (radius - 4.0),
        math.sin(angleRad) * (radius - 4.0),
      );
      final inner = Offset(
        math.cos(angleRad) * (radius - 4.0 - tickLen),
        math.sin(angleRad) * (radius - 4.0 - tickLen),
      );

      final tickPaint = Paint()
        ..strokeWidth = isCardinal ? 2.2 : (isMajor ? 1.5 : 1.0)
        ..strokeCap = StrokeCap.round
        ..color = deg == 0
            ? theme.dangerColor
            : (isMajor
                  ? theme.textPrimaryColor.withValues(alpha: 0.8)
                  : theme.textSecondaryColor.withValues(alpha: 0.42));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // North crimson accent triangle.
    final northTip = Offset(0.0, -(radius - 13.0));
    final northTriangle = Path()
      ..moveTo(northTip.dx, northTip.dy - 7.0)
      ..lineTo(northTip.dx - 4.8, northTip.dy + 2.0)
      ..lineTo(northTip.dx + 4.8, northTip.dy + 2.0)
      ..close();
    canvas.drawPath(northTriangle, Paint()..color = theme.dangerColor);

    // Cardinal letters kept upright for legibility.
    const cardinals = <(String, double)>[
      ('N', 0.0),
      ('E', 90.0),
      ('S', 180.0),
      ('W', 270.0),
    ];
    for (final entry in cardinals) {
      final label = entry.$1;
      final deg = entry.$2;
      final angleRad = GeoMath.toRadians(deg - 90.0);
      final labelRadius = radius * 0.72;
      final offset = Offset(
        math.cos(angleRad) * labelRadius,
        math.sin(angleRad) * labelRadius,
      );

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(GeoMath.toRadians(headingDegrees));
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: math.max(10.0, radius * 0.155),
            fontWeight: FontWeight.w800,
            color: label == 'N' ? theme.dangerColor : theme.textPrimaryColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2.0, -tp.height / 2.0));
      canvas.restore();
    }

    // Optional target waypoint bearing bug.
    if (targetBearingDegrees != null) {
      final targetRad = GeoMath.toRadians(targetBearingDegrees! - 90.0);
      final markerPos = Offset(
        math.cos(targetRad) * (radius - 9.0),
        math.sin(targetRad) * (radius - 9.0),
      );
      canvas.drawCircle(
        markerPos,
        5.0,
        Paint()..color = theme.warningColor.withValues(alpha: 0.28),
      );
      canvas.drawCircle(markerPos, 3.2, Paint()..color = theme.warningColor);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GeoCompassPainter oldDelegate) {
    return oldDelegate.headingDegrees != headingDegrees ||
        oldDelegate.targetBearingDegrees != targetBearingDegrees ||
        oldDelegate.theme != theme;
  }
}
