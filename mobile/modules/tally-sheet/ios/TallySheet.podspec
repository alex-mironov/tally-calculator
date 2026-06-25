Pod::Spec.new do |s|
  s.name           = 'TallySheet'
  s.version        = '1.0.0'
  s.summary        = 'Native SwiftUI name + tag sheet for Tally'
  s.description    = 'Presents the Save/Edit-tags bottom sheet as a native SwiftUI form (UISheetPresentationController).'
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
