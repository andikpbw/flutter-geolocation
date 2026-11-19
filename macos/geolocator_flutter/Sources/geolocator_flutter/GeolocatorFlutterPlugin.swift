import Cocoa
import CoreLocation
import FlutterMacOS

public class GeolocatorFlutterPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private static let methodChannelName = "id.humanize.geolocator_flutter/methods"
  private static let positionChannelName = "id.humanize.geolocator_flutter/positions"
  private static let serviceChannelName = "id.humanize.geolocator_flutter/service_status"

  private let locationManager = CLLocationManager()
  private var pendingPermissionResult: FlutterResult?
  private var pendingPositionResult: FlutterResult?
  private var positionEventSink: FlutterEventSink?
  private var serviceEventSink: FlutterEventSink?
  private var isStreamingPositions = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = GeolocatorFlutterPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let positionChannel = FlutterEventChannel(
      name: positionChannelName,
      binaryMessenger: registrar.messenger
    )
    positionChannel.setStreamHandler(MacPositionStreamHandler(plugin: instance))

    let serviceChannel = FlutterEventChannel(
      name: serviceChannelName,
      binaryMessenger: registrar.messenger
    )
    serviceChannel.setStreamHandler(MacServiceStatusStreamHandler(plugin: instance))
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
      requestLocationPermission(result: result)
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
      guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
        result(false)
        return
      }
      result(NSWorkspace.shared.open(url))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(macOS 11.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func permissionString(for status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
      return "always"
    case .denied, .restricted:
      return "deniedForever"
    case .notDetermined:
      return "denied"
    default:
      return "whileInUse"
    }
  }

  private func requestLocationPermission(result: @escaping FlutterResult) {
    let status = currentAuthorizationStatus()
    if status == .authorizedAlways {
      result("always")
      return
    }
    if status == .denied || status == .restricted {
      result("deniedForever")
      return
    }
    pendingPermissionResult = result
    if #available(macOS 10.15, *) {
      locationManager.requestWhenInUseAuthorization()
    } else {
      locationManager.startUpdatingLocation()
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
    configureManager(args: args)
    pendingPositionResult = result
    locationManager.requestLocation()
  }

  fileprivate func startStreaming(args: [String: Any], sink: @escaping FlutterEventSink) {
    guard CLLocationManager.locationServicesEnabled() else {
      sink(FlutterError(code: "SERVICE_DISABLED", message: "Location services are disabled.", details: nil))
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
    let status = currentAuthorizationStatus()
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
    if #available(macOS 10.15, *) {
      map["headingAccuracy"] = location.courseAccuracy >= 0 ? location.courseAccuracy : 0.0
      map["speedAccuracy"] = location.speedAccuracy >= 0 ? location.speedAccuracy : 0.0
    }
    return map
  }
}

private final class MacPositionStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: GeolocatorFlutterPlugin?

  init(plugin: GeolocatorFlutterPlugin) {
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

private final class MacServiceStatusStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: GeolocatorFlutterPlugin?

  init(plugin: GeolocatorFlutterPlugin) {
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
