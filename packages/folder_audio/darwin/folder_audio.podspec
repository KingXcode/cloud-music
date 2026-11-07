#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint folder_audio.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'folder_audio'
  s.version          = '0.0.1'
  s.summary          = 'Read-only folder audio playback for iOS and macOS.'
  s.description      = <<-DESC
Security-scoped folder indexing and original-URL AVFoundation playback.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'folder_audio/Sources/folder_audio/**/*.swift'

  # Set the deployment targets for both iOS and macOS.
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  # Define the platform-specific dependencies.
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  # Flutter.framework does not contain a i386 slice, which is specific to iOS.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'folder_audio_privacy' => ['folder_audio/Sources/folder_audio/PrivacyInfo.xcprivacy']}
end
