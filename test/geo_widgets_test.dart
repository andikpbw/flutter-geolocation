import 'package:flutter/widgets.dart';
import 'package:flutter_geolocation/flutter_geolocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final samplePosition = GeoPosition.fromLatLng(
    latitude: -6.175392,
    longitude: 106.827153,
    accuracy: 3.4,
    altitude: 22.5,
    heading: 48.0,
    speed: 14.5,
    provider: GeoProvider.gps,
  );

  Widget wrap(Widget child, {GeoTheme? theme}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GeoThemeScope(
        theme: theme ?? GeoTheme.dark(),
        child: Center(child: child),
      ),
    );
  }

  testWidgets('GeoStatusBadge displays accuracy and standby states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GeoStatusBadge(position: samplePosition, isTracking: true),
            const GeoStatusBadge(isTracking: true),
            GeoStatusBadge(position: samplePosition, compact: true),
          ],
        ),
      ),
    );

    expect(find.text('EXCELLENT • ±3.4m'), findsOneWidget);
    expect(find.text('ACQUIRING FIX'), findsOneWidget);
    expect(find.text('±3.4m'), findsOneWidget);
  });

  testWidgets('GeoCompassWidget renders heading and animates across north', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const GeoCompassWidget(
          headingDegrees: 350.0,
          targetBearingDegrees: 42.0,
          size: 160.0,
        ),
      ),
    );
    expect(find.text('350°'), findsOneWidget);
    expect(find.text('N'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const GeoCompassWidget(
          headingDegrees: 10.0,
          targetBearingDegrees: 42.0,
          size: 160.0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('010°'), findsOneWidget);
  });

  testWidgets('GeoRadarWidget paints trail, geofences, and waypoints cleanly', (
    WidgetTester tester,
  ) async {
    final geofences = <GeofenceRegion>[
      CircularGeofence(
        id: 'monas',
        name: 'Monas',
        center: samplePosition.coordinate,
        radiusMeters: 150.0,
      ),
      PolygonGeofence(
        id: 'park',
        polygon: GeoPolygon(<GeoCoordinate>[
          GeoCoordinate(-6.176, 106.826),
          GeoCoordinate(-6.176, 106.828),
          GeoCoordinate(-6.174, 106.828),
          GeoCoordinate(-6.174, 106.826),
        ]),
      ),
    ];

    await tester.pumpWidget(
      wrap(
        GeoRadarWidget(
          position: samplePosition,
          trail: SimulatedGeolocationPlatform.defaultJakartaRoute,
          geofences: geofences,
          waypoints: <GeoWaypoint>[
            GeoWaypoint(
              coordinate: samplePosition.coordinate.destinationPoint(
                distanceMeters: 200.0,
                bearingDegrees: 60.0,
              ),
              label: 'TARGET',
              isTarget: true,
            ),
          ],
          animateSweep: false,
          sweepAngleRadians: 1.2,
          size: 240.0,
        ),
      ),
    );

    expect(find.byType(GeoRadarWidget), findsOneWidget);
  });

  testWidgets('GeoTelemetryCard cycles coordinate formats on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 440.0,
          child: GeoTelemetryCard(
            position: samplePosition,
            isTracking: true,
            activeGeofences: <GeofenceRegion>[
              CircularGeofence(
                id: 'monas',
                name: 'Monas Core',
                center: samplePosition.coordinate,
                radiusMeters: 150.0,
              ),
            ],
          ),
        ),
        theme: GeoTheme.light(),
      ),
    );

    expect(find.text('DD'), findsOneWidget);
    expect(find.text('INSIDE • Monas Core'), findsOneWidget);

    await tester.tap(find.text('DD'));
    await tester.pump();
    expect(find.text('DMS'), findsOneWidget);

    await tester.tap(find.text('DMS'));
    await tester.pump();
    expect(find.text('DDM'), findsOneWidget);

    await tester.tap(find.text('DDM'));
    await tester.pump();
    expect(find.text('GEOHASH'), findsOneWidget);
  });

  testWidgets('GeoLocationBuilder reacts to GeoController updates', (
    WidgetTester tester,
  ) async {
    final controller = GeoController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        GeoLocationBuilder(
          controller: controller,
          loadingBuilder: (BuildContext _) => const Text('LOADING'),
          builder: (BuildContext _, GeoPosition pos) =>
              Text('FIX:${pos.latitude.toStringAsFixed(2)}'),
        ),
      ),
    );

    expect(find.text('LOADING'), findsOneWidget);

    controller.pushPosition(samplePosition);
    await tester.pump();
    expect(find.text('FIX:-6.18'), findsOneWidget);
  });
}
