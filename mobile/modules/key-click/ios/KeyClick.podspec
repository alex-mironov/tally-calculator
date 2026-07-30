Pod::Spec.new do |s|
  s.name           = 'KeyClick'
  s.version        = '1.0.0'
  s.summary        = 'Standard keyboard click sound for Tally\'s custom keypad'
  s.description    = 'Wraps UIDevice.playInputClick() so the keypad tock honours Settings > Sounds > Keyboard Clicks.'
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
