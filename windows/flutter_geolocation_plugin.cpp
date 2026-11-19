#include "flutter_geolocation_plugin.h"

#include <windows.h>
#include <shellapi.h>
#include <winrt/Windows.Devices.Geolocation.h>
#include <winrt/Windows.Foundation.h>

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <memory>
#include <mutex>
#include <string>

namespace flutter_geolocation {

namespace {

using winrt::Windows::Devices::Geolocation::GeolocationAccessStatus;
using winrt::Windows::Devices::Geolocation::Geolocator;
using winrt::Windows::Devices::Geolocation::Geoposition;
using winrt::Windows::Devices::Geolocation::PositionAccuracy;
using winrt::Windows::Devices::Geolocation::PositionStatus;

flutter::EncodableMap PositionToMap(const Geoposition& position) {
  auto coord = position.Coordinate();
  auto point = coord.Point().Position();
  auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch())
                    .count();

  double heading = 0.0;
  if (coord.Heading()) {
    heading = coord.Heading().Value();
  }
  double speed = 0.0;
  if (coord.Speed()) {
    speed = coord.Speed().Value();
  }
  double alt_accuracy = 0.0;
  if (coord.AltitudeAccuracy()) {
    alt_accuracy = coord.AltitudeAccuracy().Value();
  }

  return flutter::EncodableMap{
      {flutter::EncodableValue("latitude"), flutter::EncodableValue(point.Latitude)},
      {flutter::EncodableValue("longitude"), flutter::EncodableValue(point.Longitude)},
      {flutter::EncodableValue("timestamp"), flutter::EncodableValue(static_cast<int64_t>(now_ms))},
      {flutter::EncodableValue("accuracy"), flutter::EncodableValue(coord.Accuracy())},
      {flutter::EncodableValue("altitude"), flutter::EncodableValue(point.Altitude)},
      {flutter::EncodableValue("altitudeAccuracy"), flutter::EncodableValue(alt_accuracy)},
      {flutter::EncodableValue("heading"), flutter::EncodableValue(heading)},
      {flutter::EncodableValue("headingAccuracy"), flutter::EncodableValue(0.0)},
      {flutter::EncodableValue("speed"), flutter::EncodableValue(speed)},
      {flutter::EncodableValue("speedAccuracy"), flutter::EncodableValue(0.0)},
      {flutter::EncodableValue("isMocked"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("provider"), flutter::EncodableValue("winrt")},
  };
}

class PositionStreamState {
 public:
  std::mutex mutex;
  Geolocator geolocator{nullptr};
  winrt::event_token token{};
  bool listening = false;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink;
};

}  // namespace

void FlutterGeolocationPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "id.humanize.flutter_geolocation/methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterGeolocationPlugin>();
  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto stream_state = std::make_shared<PositionStreamState>();
  auto position_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "id.humanize.flutter_geolocation/positions",
          &flutter::StandardMethodCodec::GetInstance());

  position_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [stream_state](
              const flutter::EncodableValue* arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(stream_state->mutex);
            stream_state->sink = std::move(events);
            stream_state->geolocator = Geolocator();
            stream_state->geolocator.DesiredAccuracy(PositionAccuracy::High);
            if (arguments && std::holds_alternative<flutter::EncodableMap>(*arguments)) {
              const auto& map = std::get<flutter::EncodableMap>(*arguments);
              auto it = map.find(flutter::EncodableValue("distanceFilterMeters"));
              if (it != map.end() && std::holds_alternative<double>(it->second)) {
                stream_state->geolocator.MovementThreshold(std::get<double>(it->second));
              }
            }
            stream_state->token = stream_state->geolocator.PositionChanged(
                [stream_state](const Geolocator&, const auto& args) {
                  std::lock_guard<std::mutex> inner_lock(stream_state->mutex);
                  if (stream_state->sink) {
                    stream_state->sink->Success(
                        flutter::EncodableValue(PositionToMap(args.Position())));
                  }
                });
            stream_state->listening = true;
            return nullptr;
          },
          [stream_state](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(stream_state->mutex);
            if (stream_state->listening && stream_state->geolocator) {
              stream_state->geolocator.PositionChanged(stream_state->token);
              stream_state->listening = false;
            }
            stream_state->sink.reset();
            return nullptr;
          }));

  auto service_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "id.humanize.flutter_geolocation/service_status",
          &flutter::StandardMethodCodec::GetInstance());
  service_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            Geolocator loc;
            bool enabled = loc.LocationStatus() != PositionStatus::Disabled;
            events->Success(flutter::EncodableValue(enabled ? "enabled" : "disabled"));
            return nullptr;
          },
          [](const flutter::EncodableValue*) { return nullptr; }));

  registrar->AddPlugin(std::move(plugin));
}

FlutterGeolocationPlugin::FlutterGeolocationPlugin() = default;
FlutterGeolocationPlugin::~FlutterGeolocationPlugin() = default;

void FlutterGeolocationPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "isLocationServiceEnabled") {
    Geolocator loc;
    result->Success(flutter::EncodableValue(
        loc.LocationStatus() != PositionStatus::Disabled));
  } else if (method == "checkPermission" || method == "requestPermission") {
    auto op = Geolocator::RequestAccessAsync();
    auto shared_result =
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
    op.Completed([shared_result](const auto& async_op, const auto&) {
      try {
        switch (async_op.GetResults()) {
          case GeolocationAccessStatus::Allowed:
            shared_result->Success(flutter::EncodableValue("whileInUse"));
            break;
          case GeolocationAccessStatus::Denied:
            shared_result->Success(flutter::EncodableValue("deniedForever"));
            break;
          default:
            shared_result->Success(flutter::EncodableValue("unableToDetermine"));
            break;
        }
      } catch (...) {
        shared_result->Success(flutter::EncodableValue("unableToDetermine"));
      }
    });
  } else if (method == "getCurrentPosition") {
    Geolocator loc;
    loc.DesiredAccuracy(PositionAccuracy::High);
    auto op = loc.GetGeopositionAsync();
    auto shared_result =
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
    op.Completed([shared_result](const auto& async_op, const auto&) {
      try {
        auto pos = async_op.GetResults();
        shared_result->Success(flutter::EncodableValue(PositionToMap(pos)));
      } catch (const winrt::hresult_error& err) {
        shared_result->Error("LOCATION_ERROR", winrt::to_string(err.message()));
      } catch (...) {
        shared_result->Error("LOCATION_ERROR", "Unable to get Windows location.");
      }
    });
  } else if (method == "getLastKnownPosition") {
    result->Success(flutter::EncodableValue());
  } else if (method == "openAppSettings" || method == "openLocationSettings") {
    auto res = reinterpret_cast<intptr_t>(
        ShellExecuteW(nullptr, L"open", L"ms-settings:privacy-location",
                      nullptr, nullptr, SW_SHOWNORMAL));
    result->Success(flutter::EncodableValue(res > 32));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_geolocation
