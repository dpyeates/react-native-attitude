require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-attitude"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package.dig("author", "name") || "Darren Yeates"

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => package["repository"]["url"].sub(/^git\+/, "").sub(/\.git$/, ""), :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  s.frameworks = "CoreMotion", "CoreLocation"

  install_modules_dependencies(s)
end
