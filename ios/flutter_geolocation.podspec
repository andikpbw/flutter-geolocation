Pod::Spec.new do |s|
  s.name             = 'flutter_geolocation'
  s.version          = '1.0.0'
  s.summary          = 'Modern, lightweight, accurate Flutter geolocation plugin.'
  s.description      = <<-DESC
Modern, lightweight, accurate Flutter geolocation library with WGS-84 geodesy,
Kalman filtering, geofencing, and live radar & compass HUD widgets.
                       DESC
  s.homepage         = 'https://humanize.id'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Humanize AI Indonesia' => 'andikpbw@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_geolocation/Sources/flutter_geolocation/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.frameworks       = 'CoreLocation'
  s.resource_bundles = { 'flutter_geolocation_privacy' => ['flutter_geolocation/Sources/flutter_geolocation/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
