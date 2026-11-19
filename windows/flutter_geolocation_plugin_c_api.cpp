#include "include/flutter_geolocation/flutter_geolocation_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_geolocation_plugin.h"

void FlutterGeolocationPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_geolocation::FlutterGeolocationPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
