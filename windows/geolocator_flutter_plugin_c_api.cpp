#include "include/geolocator_flutter/geolocator_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "geolocator_flutter_plugin.h"

void GeolocatorFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  geolocator_flutter::GeolocatorFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
