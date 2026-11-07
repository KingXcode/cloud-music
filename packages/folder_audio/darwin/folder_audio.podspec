#
# Podspec 的详细说明见 http://guides.cocoapods.org/syntax/podspec.html。
# 发布前执行 `pod lib lint folder_audio.podspec` 进行验证。
#
Pod::Spec.new do |s|
  s.name             = 'folder_audio'
  s.version          = '0.0.1'
  s.summary          = '面向 iOS 和 macOS 的只读文件夹音频播放。'
  s.description      = <<-DESC
通过安全作用域建立文件夹索引，并使用 AVFoundation 播放原始 URL。
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'folder_audio/Sources/folder_audio/**/*.swift'

  # 设置 iOS 和 macOS 的最低部署版本。
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  # 定义各平台专用依赖。
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  # Flutter.framework 不包含 i386 架构切片，此配置仅适用于 iOS。
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  # 如果插件需要隐私清单，例如使用了需要声明理由的 API，
  # 请更新 PrivacyInfo.xcprivacy，说明插件对隐私的影响，
  # 然后取消下方配置行的注释。更多信息见
  # https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'folder_audio_privacy' => ['folder_audio/Sources/folder_audio/PrivacyInfo.xcprivacy']}
end
