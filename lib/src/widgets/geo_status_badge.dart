import 'package:flutter/widgets.dart';

import '../core/geo_position.dart';
import 'geo_theme.dart';

/// Compact pill badge displaying live GPS lock status, signal strength bars,
/// and horizontal accuracy in meters.
class GeoStatusBadge extends StatelessWidget {
  /// Creates a [GeoStatusBadge].
  const GeoStatusBadge({
    super.key,
    this.position,
    this.isTracking = false,
    this.theme,
    this.compact = false,
  });

  /// Current position fix, or `null` while acquiring a lock.
  final GeoPosition? position;

  /// Whether live tracking is currently active.
  final bool isTracking;

  /// Optional theme override; falls back to [GeoTheme.of].
  final GeoTheme? theme;

  /// Whether to render a shorter label without the quality descriptor.
  final bool compact;

  Color _qualityColor(GeoSignalQuality quality, GeoTheme resolved) {
    switch (quality) {
      case GeoSignalQuality.excellent:
        return resolved.successColor;
      case GeoSignalQuality.good:
        return resolved.primaryColor;
      case GeoSignalQuality.fair:
        return resolved.warningColor;
      case GeoSignalQuality.poor:
      case GeoSignalQuality.weak:
        return resolved.dangerColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = theme ?? GeoTheme.of(context);
    final pos = position;
    final quality = pos?.signalQuality ?? GeoSignalQuality.weak;
    final accent = pos != null
        ? _qualityColor(quality, resolved)
        : (isTracking ? resolved.warningColor : resolved.textSecondaryColor);

    final String label;
    if (pos == null) {
      label = isTracking ? 'ACQUIRING FIX' : 'STANDBY';
    } else if (compact) {
      label = '±${pos.accuracy.toStringAsFixed(1)}m';
    } else {
      label =
          '${quality.label.toUpperCase()} • ±${pos.accuracy.toStringAsFixed(1)}m';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7.0,
              height: 7.0,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.65),
                    blurRadius: 6.0,
                    spreadRadius: 1.0,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7.0),
            _SignalBars(
              activeBars: pos == null ? 0 : quality.bars,
              activeColor: accent,
              inactiveColor: resolved.textSecondaryColor.withValues(
                alpha: 0.28,
              ),
            ),
            const SizedBox(width: 7.0),
            Text(
              label,
              style: TextStyle(
                fontFamily: resolved.fontFamily,
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.55,
                color: accent,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({
    required this.activeBars,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int activeBars;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(4, (int index) {
        final height = 4.0 + index * 2.5;
        final isActive = index < activeBars;
        return Padding(
          padding: EdgeInsets.only(right: index < 3 ? 1.8 : 0.0),
          child: Container(
            width: 2.6,
            height: height,
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(1.2),
            ),
          ),
        );
      }),
    );
  }
}
