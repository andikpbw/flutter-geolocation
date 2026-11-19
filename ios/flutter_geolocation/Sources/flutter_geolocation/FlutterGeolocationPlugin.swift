import CoreLocation
import Flutter
import UIKit

public class FlutterGeolocationPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private static let methodChannelName = "id.humanize.flutter_geolocation/methods"
  private static let positionChannelName = "id.humanize.flutter_geolocation/positions"
  private static let serviceChannelName = "id.humanize.flutter_geolocation/service_status"

  private let locationManager = CLLocationManager()
  private var pendingPermissionResult: FlutterResult?
  private var pendingPositionResult: FlutterResult?
  private var positionEventSink: FlutterEventSink?
  private var serviceEventSink: FlutterEventSink?
  private var isStreamingPositions = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterGeolocationPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let positionChannel = FlutterEventChannel(
      name: positionChannelName,
      binaryMessenger: registrar.messenger()
    )
    positionChannel.setStreamHandler(PositionStreamHandler(plugin: instance))

    let serviceChannel = FlutterEventChannel(
      name: serviceChannelName,
      binaryMessenger: registrar.messenger()
    )
    serviceChannel.setStreamHandler(ServiceStatusStreamHandler(plugin: instance))
  }

  override init() {
    super.init()
    locationManager.delegate = self
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isLocationServiceEnabled":
      result(CLLocationManager.locationServicesEnabled())
    case "checkPermission":
      result(permissionString(for: currentAuthorizationStatus()))
    case "requestPermission":
      let args = call.arguments as? [String: Any]
      let always = args?["always"] as? Bool ?? false
      requestLocationPermission(always: always, result: result)
    case "getLastKnownPosition":
      if let loc = locationManager.location {
        result(locationToMap(loc))
      } else {
        result(nil)
      }
    case "getCurrentPosition":
      let args = call.arguments as? [String: Any] ?? [:]
      fetchCurrentPosition(args: args, result: result)
    case "openAppSettings", "openLocationSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { success in
        result(success)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func permissionString(for status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
      return "always"
    case .authorizedWhenInUse:
      return "whileInUse"
    case .denied, .restricted:
      return "deniedForever"
    case .notDetermined:
      return "denied"
    @unknown default:
      return "unableToDetermine"
    }
  }

  private func requestLocationPermission(always: Bool, result: @escaping FlutterResult) {
    let status = currentAuthorizationStatus()
    if status == .authorizedAlways || (status == .authorizedWhenInUse && !always) {
      result(permissionString(for: status))
      return
    }
    if status == .denied || status == .restricted {
      result("deniedForever")
      return
    }
    pendingPermissionResult = result
    if always {
      locationManager.requestAlwaysAuthorization()
    } else {
      locationManager.requestWhenInUseAuthorization()
    }
  }

  private func configureManager(args: [String: Any]) {
    let accuracyName = args["accuracy"] as? String ?? "high"
    switch accuracyName {
    case "lowest":
      locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    case "low":
      locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    case "medium":
      locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    case "high":
      locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    case "best":
      locationManager.desiredAccuracy = kCLLocationAccuracyBest
    case "navigation":
      locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    default:
      locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    let distanceFilter = (args["distanceFilterMeters"] as? NSNumber)?.doubleValue ?? 0.0
    locationManager.distanceFilter = distanceFilter > 0 ? distanceFilter : kCLDistanceFilterNone
  }

  private func fetchCurrentPosition(args: [String: Any], result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(code: "SERVICE_DISABLED", message: "Location services are disabled.", details: nil))
      return
    }
    let status = currentAuthorizationStatus()
    guard status == .authorizedWhenInUse || status == .authorizedAlways else {
      let code = (status == .denied || status == .restricted) ? "PERMISSION_DENIED_FOREVER" : "PERMISSION_DENIED"
      result(FlutterError(code: code, message: "Location permission is not granted.", details: nil))
      return
    }
    configureManager(args: args)
    pendingPositionResult = result
    locationManager.requestLocation()
  }

  fileprivate func startStreaming(args: [String: Any], sink: @escaping FlutterEventSink) {
    guard CLLocationManager.locationServicesEnabled() else {
      sink(FlutterError(code: "SERVICE_DISABLED", message: "Location services are disabled.", details: nil))
      return
    }
    let status = currentAuthorizationStatus()
    guard status == .authorizedWhenInUse || status == .authorizedAlways else {
      let code = (status == .denied || status == .restricted) ? "PERMISSION_DENIED_FOREVER" : "PERMISSION_DENIED"
      sink(FlutterError(code: code, message: "Location permission is not granted.", details: nil))
      return
    }
    configureManager(args: args)
    positionEventSink = sink
    isStreamingPositions = true
    locationManager.startUpdatingLocation()
  }

  fileprivate func stopStreaming() {
    isStreamingPositions = false
    positionEventSink = nil
    locationManager.stopUpdatingLocation()
  }

  fileprivate func startServiceStatus(sink: @escaping FlutterEventSink) {
    serviceEventSink = sink
    sink(CLLocationManager.locationServicesEnabled() ? "enabled" : "disabled")
  }

  fileprivate func stopServiceStatus() {
    serviceEventSink = nil
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    handleAuthorizationChange(currentAuthorizationStatus())
  }

  public func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    handleAuthorizationChange(status)
  }

  private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
    if let pending = pendingPermissionResult, status != .notDetermined {
      pendingPermissionResult = nil
      pending(permissionString(for: status))
    }
    serviceEventSink?(CLLocationManager.locationServicesEnabled() ? "enabled" : "disabled")
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let latest = locations.last else { return }
    let payload = locationToMap(latest)
    if let pending = pendingPositionResult {
      pendingPositionResult = nil
      pending(payload)
    }
    if isStreamingPositions {
      positionEventSink?(payload)
    }
  }

  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let flError = FlutterError(
      code: "LOCATION_ERROR",
      message: error.localizedDescription,
      details: nil
    )
    if let pending = pendingPositionResult {
      pendingPositionResult = nil
      pending(flError)
    }
    if isStreamingPositions {
      positionEventSink?(flError)
    }
  }

  private func locationToMap(_ location: CLLocation) -> [String: Any] {
    var map: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000.0),
      "accuracy": max(0.0, location.horizontalAccuracy),
      "altitude": location.altitude,
      "altitudeAccuracy": max(0.0, location.verticalAccuracy),
      "heading": location.course >= 0 ? location.course : 0.0,
      "speed": location.speed >= 0 ? location.speed : 0.0,
      "isMocked": false,
      "provider": "corelocation",
    ]
    if #available(iOS 13.4, *) {
      map["headingAccuracy"] = location.courseAccuracy >= 0 ? location.courseAccuracy : 0.0
    }
    if #available(iOS 10.0, *) {
      map["speedAccuracy"] = location.speedAccuracy >= 0 ? location.speedAccuracy : 0.0
    }
    if #available(iOS 15.0, *), let sourceInfo = location.sourceInformation {
      map["isMocked"] = sourceInfo.isSimulatedBySoftware || sourceInfo.isProducedByAccessory
    }
    if let floor = location.floor {
      map["floor"] = floor.level
    }
    return map
  }
}

private final class PositionStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: FlutterGeolocationPlugin?

  init(plugin: FlutterGeolocationPlugin) {
    self.plugin = plugin
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    let args = arguments as? [String: Any] ?? [:]
    plugin?.startStreaming(args: args, sink: events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.stopStreaming()
    return nil
  }
}

private final class ServiceStatusStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: FlutterGeolocationPlugin?

  init(plugin: FlutterGeolocationPlugin) {
    self.plugin = plugin
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    plugin?.startServiceStatus(sink: events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.stopServiceStatus()
    return nil
  }
}
