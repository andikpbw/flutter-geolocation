import 'package:flutter/widgets.dart';

/// Visual theme configuration for all `geolocator_flutter` UI widgets.
///
/// Built purely on `package:flutter/widgets.dart` so widgets integrate cleanly
/// into any Flutter application without depending on Material or Cupertino.
@immutable
class GeoTheme {
  /// Creates a custom [GeoTheme].
  const GeoTheme({
    required this.backgroundColor,
    required this.surfaceColor,
    required this.borderColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.successColor,
    required this.warningColor,
    required this.dangerColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.gridColor,
    this.borderRadius = 20.0,
    this.fontFamily,
  });

  /// Modern obsidian dark theme tailored for tactical HUD and map overlays.
  factory GeoTheme.dark() => const GeoTheme(
    backgroundColor: Color(0xFF070D19),
    surfaceColor: Color(0xFF0F182A),
    borderColor: Color(0xFF1F2F4D),
    primaryColor: Color(0xFF22D3EE),
    secondaryColor: Color(0xFF38BDF8),
    successColor: Color(0xFF10B981),
    warningColor: Color(0xFFF59E0B),
    dangerColor: Color(0xFFF43F5E),
    textPrimaryColor: Color(0xFFF8FAFC),
    textSecondaryColor: Color(0xFF94A3B8),
    gridColor: Color(0xFF1E3A5F),
  );

  /// Clean daylight light theme for bright outdoor environments.
  factory GeoTheme.light() => const GeoTheme(
    backgroundColor: Color(0xFFF1F5F9),
    surfaceColor: Color(0xFFFFFFFF),
    borderColor: Color(0xFFCBD5E1),
    primaryColor: Color(0xFF0284C7),
    secondaryColor: Color(0xFF0EA5E9),
    successColor: Color(0xFF059669),
    warningColor: Color(0xFFD97706),
    dangerColor: Color(0xFFE11D48),
    textPrimaryColor: Color(0xFF0F172A),
    textSecondaryColor: Color(0xFF475569),
    gridColor: Color(0xFFCBD5E1),
  );

  /// Outer canvas background color.
  final Color backgroundColor;

  /// Elevated card and instrument dial surface color.
  final Color surfaceColor;

  /// Hairline border stroke color.
  final Color borderColor;

  /// Primary luminous accent color (radar sweep, active trail, highlights).
  final Color primaryColor;

  /// Secondary accent color (supporting rings and telemetry highlights).
  final Color secondaryColor;

  /// Positive status color (excellent GPS lock, active geofence inside).
  final Color successColor;

  /// Caution status color (fair GPS accuracy, target waypoint highlight).
  final Color warningColor;

  /// Critical status color (north pointer, weak GPS signal, error state).
  final Color dangerColor;

  /// Primary high-contrast foreground text color.
  final Color textPrimaryColor;

  /// Secondary muted caption and label color.
  final Color textSecondaryColor;

  /// Instrument grid, range rings, and crosshair stroke color.
  final Color gridColor;

  /// Corner radius for cards and containers.
  final double borderRadius;

  /// Optional custom font family applied to widget text styles.
  final String? fontFamily;

  /// Resolves the nearest [GeoTheme] from [GeoThemeScope], falling back to
  /// [GeoTheme.dark].
  static GeoTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GeoThemeScope>();
    return scope?.theme ?? GeoTheme.dark();
  }

  /// Creates a copy of this theme with selectively overridden fields.
  GeoTheme copyWith({
    Color? backgroundColor,
    Color? surfaceColor,
    Color? borderColor,
    Color? primaryColor,
    Color? secondaryColor,
    Color? successColor,
    Color? warningColor,
    Color? dangerColor,
    Color? textPrimaryColor,
    Color? textSecondaryColor,
    Color? gridColor,
    double? borderRadius,
    String? fontFamily,
  }) {
    return GeoTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      borderColor: borderColor ?? this.borderColor,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      successColor: successColor ?? this.successColor,
      warningColor: warningColor ?? this.warningColor,
      dangerColor: dangerColor ?? this.dangerColor,
      textPrimaryColor: textPrimaryColor ?? this.textPrimaryColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      gridColor: gridColor ?? this.gridColor,
      borderRadius: borderRadius ?? this.borderRadius,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoTheme &&
        other.backgroundColor == backgroundColor &&
        other.surfaceColor == surfaceColor &&
        other.borderColor == borderColor &&
        other.primaryColor == primaryColor &&
        other.secondaryColor == secondaryColor &&
        other.successColor == successColor &&
        other.warningColor == warningColor &&
        other.dangerColor == dangerColor &&
        other.textPrimaryColor == textPrimaryColor &&
        other.textSecondaryColor == textSecondaryColor &&
        other.gridColor == gridColor &&
        other.borderRadius == borderRadius &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    surfaceColor,
    borderColor,
    primaryColor,
    secondaryColor,
    successColor,
    warningColor,
    dangerColor,
    textPrimaryColor,
    textSecondaryColor,
    gridColor,
    borderRadius,
    fontFamily,
  );
}

/// Inherited scope providing a [GeoTheme] to descendant `geolocator_flutter`
/// widgets.
class GeoThemeScope extends InheritedWidget {
  /// Creates a [GeoThemeScope].
  const GeoThemeScope({required this.theme, required super.child, super.key});

  /// Theme exposed to descendant widgets.
  final GeoTheme theme;

  @override
  bool updateShouldNotify(GeoThemeScope oldWidget) => theme != oldWidget.theme;
}
