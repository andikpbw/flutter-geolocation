import 'dart:convert';

import 'package:flutter_geolocation/flutter_geolocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoKalmanFilter', () {
    test('reduces GPS noise variance while tracking real motion', () {
      final filter = GeoKalmanFilter(processNoiseMetersPerSecond: 2.0);
      final base = GeoCoordinate(-6.175392, 106.827153);
      final t0 = DateTime.utc(2026, 11, 19, 12);

      // Alternating ±15m jitter around a stationary point with 15m accuracy.
      final rawErrors = <double>[];
      final filteredErrors = <double>[];
      for (var i = 0; i < 20; i++) {
        final noisy = base.destinationPoint(
          distanceMeters: 15.0,
          bearingDegrees: i.isEven ? 90.0 : 270.0,
        );
        final rawPos = GeoPosition(
          coordinate: noisy,
          timestamp: t0.add(Duration(seconds: i)),
          accuracy: 15.0,
        );
        final out = filter.process(rawPos)!;
        rawErrors.add(base.distanceTo(rawPos.coordinate));
        filteredErrors.add(base.distanceTo(out.coordinate));
      }

      // After warm-up, filtered error must be far smaller than raw 15m error.
      expect(filteredErrors.last, lessThan(rawErrors.last * 0.5));
    });

    test(
      'rejects transient teleportation spikes and re-anchors on real jumps',
      () {
        final filter = GeoKalmanFilter(
          maxSpeedMetersPerSecond: 80.0,
          reanchorAfterConsecutiveOutliers: 3,
        );
        final t0 = DateTime.utc(2026, 11, 19, 12);
        final jakarta = GeoCoordinate(-6.175392, 106.827153);
        final bandung = GeoCoordinate(-6.917464, 107.619123);

        expect(
          filter.process(
            GeoPosition(coordinate: jakarta, timestamp: t0, accuracy: 5.0),
          ),
          isNotNull,
        );

        // Single impossible 120 km jump in 1 second -> rejected.
        expect(
          filter.process(
            GeoPosition(
              coordinate: bandung,
              timestamp: t0.add(const Duration(seconds: 1)),
              accuracy: 5.0,
            ),
          ),
          isNull,
        );

        // Second consecutive jump -> still rejected.
        expect(
          filter.process(
            GeoPosition(
              coordinate: bandung,
              timestamp: t0.add(const Duration(seconds: 2)),
              accuracy: 5.0,
            ),
          ),
          isNull,
        );

        // Third consecutive fix at new location -> re-anchors cleanly.
        final reanchored = filter.process(
          GeoPosition(
            coordinate: bandung,
            timestamp: t0.add(const Duration(seconds: 3)),
            accuracy: 5.0,
          ),
        );
        expect(reanchored, isNotNull);
        expect(reanchored!.coordinate.distanceTo(bandung), lessThan(1.0));
      },
    );
  });

  group('GeofenceEngine', () {
    test('fires enter, dwell, and hysteresis-guarded exit events', () async {
      final center = GeoCoordinate(-6.175392, 106.827153);
      final zone = CircularGeofence(
        id: 'monas',
        name: 'Monas',
        center: center,
        radiusMeters: 100.0,
        hysteresisMeters: 20.0,
        dwellDuration: const Duration(seconds: 10),
      );
      final engine = GeofenceEngine(regions: <GeofenceRegion>[zone]);
      final emitted = <GeofenceEvent>[];
      final sub = engine.events.listen(emitted.add);

      final t0 = DateTime.utc(2026, 11, 19, 12);

      // 1. Outside (150m away) -> no event.
      expect(
        engine.processPosition(
          GeoPosition(
            coordinate: center.destinationPoint(
              distanceMeters: 150.0,
              bearingDegrees: 0.0,
            ),
            timestamp: t0,
          ),
        ),
        isEmpty,
      );

      // 2. Inside (50m away) -> ENTER.
      final enterEvents = engine.processPosition(
        GeoPosition(
          coordinate: center.destinationPoint(
            distanceMeters: 50.0,
            bearingDegrees: 0.0,
          ),
          timestamp: t0.add(const Duration(seconds: 1)),
        ),
      );
      expect(enterEvents.single.transition, GeofenceTransition.enter);
      expect(engine.isInside('monas'), isTrue);

      // 3. Slightly outside (110m away, within 20m hysteresis) -> stays INSIDE.
      final hysteresisEvents = engine.processPosition(
        GeoPosition(
          coordinate: center.destinationPoint(
            distanceMeters: 110.0,
            bearingDegrees: 0.0,
          ),
          timestamp: t0.add(const Duration(seconds: 5)),
        ),
      );
      expect(hysteresisEvents, isEmpty);
      expect(engine.isInside('monas'), isTrue);

      // 4. Still inside after 10s dwell duration -> DWELL.
      final dwellEvents = engine.processPosition(
        GeoPosition(
          coordinate: center,
          timestamp: t0.add(const Duration(seconds: 12)),
        ),
      );
      expect(dwellEvents.single.transition, GeofenceTransition.dwell);

      // 5. Beyond radius + hysteresis (125m) -> EXIT.
      final exitEvents = engine.processPosition(
        GeoPosition(
          coordinate: center.destinationPoint(
            distanceMeters: 125.0,
            bearingDegrees: 0.0,
          ),
          timestamp: t0.add(const Duration(seconds: 15)),
        ),
      );
      expect(exitEvents.single.transition, GeofenceTransition.exit);
      expect(engine.isInside('monas'), isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(emitted.length, 3);
      await sub.cancel();
      await engine.dispose();
    });

    test('supports PolygonGeofence enter and exit', () async {
      final polyZone = PolygonGeofence(
        id: 'campus',
        polygon: GeoPolygon(<GeoCoordinate>[
          GeoCoordinate(0.0, 0.0),
          GeoCoordinate(0.0, 0.01),
          GeoCoordinate(0.01, 0.01),
          GeoCoordinate(0.01, 0.0),
        ]),
      );
      final engine = GeofenceEngine(regions: <GeofenceRegion>[polyZone]);
      final t0 = DateTime.utc(2026, 11, 19, 12);

      final ev1 = engine.processPosition(
        GeoPosition(coordinate: GeoCoordinate(0.005, 0.005), timestamp: t0),
      );
      expect(ev1.single.transition, GeofenceTransition.enter);

      final ev2 = engine.processPosition(
        GeoPosition(
          coordinate: GeoCoordinate(0.02, 0.02),
          timestamp: t0.add(const Duration(seconds: 5)),
        ),
      );
      expect(ev2.single.transition, GeofenceTransition.exit);
      await engine.dispose();
    });
  });

  group('GeoTrackRecorder', () {
    test('records distance, speed, elevation, GeoJSON, and GPX accurately', () {
      final recorder = GeoTrackRecorder(
        minDisplacementMeters: 2.0,
        maxAccuracyMeters: 30.0,
      );
      final t0 = DateTime.utc(2026, 11, 19, 12);
      final start = GeoCoordinate(-6.175392, 106.827153);

      // Ignored while idle.
      expect(
        recorder.record(
          GeoPosition(coordinate: start, timestamp: t0, accuracy: 4.0),
        ),
        isFalse,
      );

      recorder.start();
      expect(
        recorder.record(
          GeoPosition(
            coordinate: start,
            timestamp: t0,
            accuracy: 4.0,
            altitude: 10.0,
            speed: 5.0,
          ),
        ),
        isTrue,
      );

      // Rejected because accuracy > 30m.
      expect(
        recorder.record(
          GeoPosition(
            coordinate: start.destinationPoint(
              distanceMeters: 50.0,
              bearingDegrees: 90.0,
            ),
            timestamp: t0.add(const Duration(seconds: 5)),
            accuracy: 80.0,
          ),
        ),
        isFalse,
      );

      // Rejected because displacement < 2m.
      expect(
        recorder.record(
          GeoPosition(
            coordinate: start.destinationPoint(
              distanceMeters: 0.5,
              bearingDegrees: 90.0,
            ),
            timestamp: t0.add(const Duration(seconds: 6)),
            accuracy: 4.0,
          ),
        ),
        isFalse,
      );

      // Accepted: 100m east, +12m altitude.
      final p2 = start.destinationPoint(
        distanceMeters: 100.0,
        bearingDegrees: 90.0,
      );
      expect(
        recorder.record(
          GeoPosition(
            coordinate: p2,
            timestamp: t0.add(const Duration(seconds: 10)),
            accuracy: 4.0,
            altitude: 22.0,
            speed: 10.0,
          ),
        ),
        isTrue,
      );

      // Accepted: another 100m east, -5m descent.
      final p3 = p2.destinationPoint(
        distanceMeters: 100.0,
        bearingDegrees: 90.0,
      );
      expect(
        recorder.record(
          GeoPosition(
            coordinate: p3,
            timestamp: t0.add(const Duration(seconds: 20)),
            accuracy: 4.0,
            altitude: 17.0,
            speed: 10.0,
          ),
        ),
        isTrue,
      );

      recorder.stop();
      final stats = recorder.stats;
      expect(stats.pointCount, 3);
      expect(stats.totalDistanceMeters, closeTo(200.0, 0.5));
      expect(stats.elapsedDuration, const Duration(seconds: 20));
      expect(stats.elevationGainMeters, closeTo(12.0, 0.01));
      expect(stats.elevationLossMeters, closeTo(5.0, 0.01));
      expect(stats.maxSpeedKmh, closeTo(36.0, 0.5));

      final geoJsonDecoded =
          jsonDecode(recorder.toGeoJson(name: 'Morning Run'))
              as Map<String, Object?>;
      expect(geoJsonDecoded['type'], 'FeatureCollection');

      final gpx = recorder.toGpx(name: 'Run & Climb <1>');
      expect(gpx, contains('<name>Run &amp; Climb &lt;1&gt;</name>'));
      expect(gpx, contains('<trkpt'));
    });
  });
}
