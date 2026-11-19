import 'package:flutter/services.dart';
import 'package:flutter_geolocation/flutter_geolocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelGeolocation', () {
    const channel = MethodChannel('id.humanize.flutter_geolocation/methods');
    late MethodChannelGeolocation platform;
    late GeolocationPlatform previousPlatform;

    setUp(() {
      previousPlatform = FlutterGeolocation.platform;
      platform = MethodChannelGeolocation();
      FlutterGeolocation.platform = platform;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      FlutterGeolocation.platform = previousPlatform;
    });

    test(
      'invokes all method channel operations and parses GeoPosition',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              switch (call.method) {
                case 'isLocationServiceEnabled':
                  return true;
                case 'checkPermission':
                  return 'whileInUse';
                case 'requestPermission':
                  return 'always';
                case 'getCurrentPosition':
                case 'getLastKnownPosition':
                  return <String, Object?>{
                    'latitude': -6.175392,
                    'longitude': 106.827153,
                    'timestamp': 1763560000000,
                    'accuracy': 4.5,
                    'altitude': 21.0,
                    'heading': 45.0,
                    'speed': 12.0,
                    'isMocked': false,
                    'provider': 'gps',
                  };
                case 'openAppSettings':
                case 'openLocationSettings':
                  return true;
                default:
                  return null;
              }
            });

        expect(await FlutterGeolocation.isLocationServiceEnabled(), isTrue);
        expect(
          await FlutterGeolocation.checkPermission(),
          GeoPermissionStatus.whileInUse,
        );
        expect(
          await FlutterGeolocation.requestPermission(always: true),
          GeoPermissionStatus.always,
        );

        final pos = await FlutterGeolocation.getCurrentPosition();
        expect(pos.latitude, closeTo(-6.175392, 1e-6));
        expect(pos.longitude, closeTo(106.827153, 1e-6));
        expect(pos.signalQuality, GeoSignalQuality.excellent);
        expect(pos.provider, GeoProvider.gps);
        expect(pos.compassDirection, CompassDirection.northeast);

        final last = await FlutterGeolocation.getLastKnownPosition();
        expect(last, isNotNull);
        expect(await FlutterGeolocation.openAppSettings(), isTrue);
        expect(await FlutterGeolocation.openLocationSettings(), isTrue);
      },
    );

    test('rejects mocked positions when allowMockLocations is false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <String, Object?>{
              'latitude': 0.0,
              'longitude': 0.0,
              'timestamp': 1763560000000,
              'isMocked': true,
            };
          });

      await expectLater(
        FlutterGeolocation.getCurrentPosition(
          settings: const GeoSettings(allowMockLocations: false),
        ),
        throwsA(isA<GeoMockLocationException>()),
      );
    });

    test(
      'maps native PlatformExceptions into sealed GeoException hierarchy',
      () {
        expect(
          MethodChannelGeolocation.mapPlatformException(
            PlatformException(code: 'PERMISSION_DENIED'),
          ),
          isA<GeoPermissionDeniedException>(),
        );
        final permanent =
            MethodChannelGeolocation.mapPlatformException(
                  PlatformException(code: 'PERMISSION_DENIED_FOREVER'),
                )
                as GeoPermissionDeniedException;
        expect(permanent.isPermanent, isTrue);

        expect(
          MethodChannelGeolocation.mapPlatformException(
            PlatformException(code: 'SERVICE_DISABLED'),
          ),
          isA<GeoServiceDisabledException>(),
        );
        expect(
          MethodChannelGeolocation.mapPlatformException(
            PlatformException(code: 'TIMEOUT'),
          ),
          isA<GeoTimeoutException>(),
        );
        expect(
          MethodChannelGeolocation.mapPlatformException(
            PlatformException(code: 'UNSUPPORTED'),
          ),
          isA<GeoUnsupportedException>(),
        );
        expect(
          MethodChannelGeolocation.mapPlatformException(
            PlatformException(code: 'OTHER'),
          ),
          isA<GeoUnknownException>(),
        );
      },
    );
  });

  group('SimulatedGeolocationPlatform & GeoController', () {
    late GeolocationPlatform previousPlatform;
    late SimulatedGeolocationPlatform simulator;

    setUp(() {
      previousPlatform = FlutterGeolocation.platform;
      simulator = SimulatedGeolocationPlatform(
        updateInterval: const Duration(milliseconds: 20),
        speedMetersPerSecond: 18.0,
        jitterMeters: 0.0,
      );
      FlutterGeolocation.platform = simulator;
    });

    tearDown(() async {
      await simulator.dispose();
      FlutterGeolocation.platform = previousPlatform;
    });

    test('streams smoothed fixes and drives GeoController cleanly', () async {
      final controller = GeoController(
        settings: const GeoSettings(
          timeInterval: Duration(milliseconds: 20),
          enableKalmanFilter: true,
        ),
        geofences: <GeofenceRegion>[
          CircularGeofence(
            id: 'start-zone',
            center: SimulatedGeolocationPlatform.defaultJakartaRoute.first,
            radiusMeters: 500.0,
          ),
        ],
      );

      await controller.startTracking();
      expect(controller.isTracking, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(controller.position, isNotNull);
      expect(controller.trail.length, greaterThanOrEqualTo(2));
      expect(controller.activeGeofences, isNotEmpty);

      await controller.stopTracking();
      expect(controller.isTracking, isFalse);

      controller.clearHistory();
      expect(controller.trail, isEmpty);
      controller.dispose();
    });

    test('reports GeoServiceDisabledException when service disabled', () async {
      simulator.setServiceEnabled(false);
      final controller = GeoController();

      final fix = await controller.refreshPosition();
      expect(fix, isNull);
      expect(controller.error, isA<GeoServiceDisabledException>());
      controller.dispose();
    });

    test('distanceBetween and bearingBetween shortcuts match WGS-84', () {
      final d = FlutterGeolocation.distanceBetween(
        -6.175392,
        106.827153,
        -6.208763,
        106.845599,
      );
      final b = FlutterGeolocation.bearingBetween(
        -6.175392,
        106.827153,
        -6.208763,
        106.845599,
      );
      expect(d, greaterThan(4100.0));
      expect(d, lessThan(4300.0));
      expect(b, greaterThan(145.0));
      expect(b, lessThan(155.0));
    });
  });
}
