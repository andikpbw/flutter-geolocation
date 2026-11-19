/// Web plugin registration library for `geolocator_flutter`.
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/platform/geolocation_platform.dart';
import 'src/platform/web_geolocation_stub.dart'
    if (dart.library.js_interop) 'src/platform/web_geolocation_impl.dart';

/// Web plugin registrant for `geolocator_flutter`.
///
/// Automatically invoked by Flutter's generated web plugin registrant to wire
/// the Wasm-ready W3C Geolocation API implementation into
/// [GeolocationPlatform.instance].
class GeolocatorFlutterWeb {
  /// Creates a [GeolocatorFlutterWeb] plugin registrant instance.
  const GeolocatorFlutterWeb();

  /// Registers the Wasm-compatible browser geolocation implementation.
  static void registerWith(Registrar registrar) {
    GeolocationPlatform.instance = createWebGeolocationPlatform();
  }
}
