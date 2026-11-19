#ifndef FLUTTER_PLUGIN_GEOLOCATOR_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_GEOLOCATOR_FLUTTER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace geolocator_flutter {

class GeolocatorFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  GeolocatorFlutterPlugin();
  virtual ~GeolocatorFlutterPlugin();

  GeolocatorFlutterPlugin(const GeolocatorFlutterPlugin&) = delete;
  GeolocatorFlutterPlugin& operator=(const GeolocatorFlutterPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace geolocator_flutter

#endif  // FLUTTER_PLUGIN_GEOLOCATOR_FLUTTER_PLUGIN_H_
