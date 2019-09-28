require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-attitude"
  s.version      = package["version"]
  s.summary      = "Obtain device attitude (roll, pitch, heading), and altitude"
  s.author       = "Darren Yeates"

  s.homepage     = "https://github.com/dpyeates/react-native-attitude"

  s.license      = "MIT"
  s.ios.deployment_target = "7.0"
  s.tvos.deployment_target = "9.0"

  s.source       = { :git => "https://github.com/dpyeates/react-native-attitude.git", :tag => "#{s.version}" }

  s.source_files  = "ios/**/*.{h,m}"
  s.requires_arc = true

  s.dependency "React"
end
