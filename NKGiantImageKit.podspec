Pod::Spec.new do |s|
  s.name	= "NKGiantImageKit"
  s.version 	= "1.0.0"
  s.license	= 'MIT'
  s.summary 	= "NKGiantImageKit is a library designed to deal with giant/large image."
  s.homepage	= "https://github.com/NearKXH/NKGiantImageKit"
  s.author   	= { "Nate Kong" => "near.kongxh@gmail.com" }
  s.source   	= { :git => "https://github.com/NearKXH/NKGiantImageKit.git", :tag => s.version }
  s.platform   	= :ios, "8.0"  
  s.requires_arc 	= true
  s.source_files 	= 'NKGiantImageKit/NKGiantImageKit.h'

  s.subspec 'Downsize' do |ss|
    ss.source_files = 'NKGiantImageKit/Downsize/**/*.{h,m}'
  end

  s.subspec 'ImageView' do |ss|
    ss.source_files = 'NKGiantImageKit/ImageView/**/*.{h,m}'
  end

end
