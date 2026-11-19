import 'package:flutter/widgets.dart';
import 'package:geolocator_flutter/geolocator_flutter.dart';
import 'package:geolocator_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GeolocationExampleApp renders wide and narrow layouts cleanly', (
    WidgetTester tester,
  ) async {
    final simulator = SimulatedGeolocationPlatform(
      updateInterval: const Duration(milliseconds: 250),
      jitterMeters: 0.0,
    );
    FlutterGeolocation.platform = simulator;
    addTearDown(simulator.dispose);

    // Wide desktop layout
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const GeolocationExampleApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('GEOLOCATOR FLUTTER'), findsOneWidget);
    expect(find.byType(GeoRadarWidget), findsOneWidget);
    expect(find.byType(GeoCompassWidget), findsOneWidget);
    expect(find.byType(GeoTelemetryCard), findsOneWidget);

    // Narrow mobile layout
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(GeoRadarWidget), findsOneWidget);
  });
}
