#ifndef FLUTTER_PLUGIN_FLUTTER_GEOLOCATION_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_GEOLOCATION_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_geolocation {

class FlutterGeolocationPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterGeolocationPlugin();
  virtual ~FlutterGeolocationPlugin();

  FlutterGeolocationPlugin(const FlutterGeolocationPlugin&) = delete;
  FlutterGeolocationPlugin& operator=(const FlutterGeolocationPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_geolocation

#endif  // FLUTTER_PLUGIN_FLUTTER_GEOLOCATION_PLUGIN_H_
