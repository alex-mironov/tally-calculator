Pod::Spec.new do |s|
  s.name           = 'ListScroll'
  s.version        = '1.0.0'
  s.summary        = 'Scroll the SwiftUI List behind an @expo/ui Host to its end'
  s.description    = 'SwiftUI .scrollPosition(id:) does not support List, so this walks the host view for the backing UIScrollView and scrolls it.'
  s.author         = ''
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = {
    :ios => '16.4',
    :tvos => '16.4'
  }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
