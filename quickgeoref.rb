# coding: utf-8
require 'optparse'
require 'rational'
require 'ruby-units'
require 'dimensions'

Unit.define("earth_radius") do |foobar|
  foobar.definition   = Unit.new("6378137.0 m")
  foobar.aliases      = %w{R_E earth_radius R_⊕ R⊕ a_E a_⊕ a⊕}
  foobar.display_name = "R⊕"
end
Unit.define("earth_polar_radius") do |foobar|
  foobar.definition   = Unit.new("6356752.3142 m")
  foobar.aliases      = %w{R_E_P earth_polar_radius R_⊕_P R⊕P b_E b_⊕ b⊕}
  foobar.display_name = "R⊕P"
end


options = {}
OptionParser.new do |opts|

  opts.accept(:length) do |v|
    unit = v.to_unit
    raise OptionParser::InvalidArgument, "Must be a distance" unless unit.kind == :length
    unit
  end
  
  opts.banner = "Usage: quickgeoref.rb [options] FILE"

  opts.on("-a", "--semi-major DISTANCE", :length, "Semi-major axis (Equatorial radius)", "Defaults to Earth's radius of 6378137.0 m") do |v|
    options[:semimajor] = v
  end
  
  opts.on("-b", "--semi-minor DISTANCE", :length, "Semi-minor axis (Polar radius)", "Defaults to being calculated from semi-major axis and flattening") do |v|
    options[:semiminor] = v
  end
  
  opts.on("-f", "--flattening N", Float, "Inverse flattening", "Defaults to Earth's value of 298.257223563 or is calculated from the semi-major and semi-minor axes") do |v|
    options[:flattening] = v
  end
  
  opts.on("--[no-]auxfile", "Create .aux.xml", "On by default") do |v|
    options[:auxfile] = v
  end
  
  opts.on("--[no-]worldfile", "Create worldfile (replace last letter of extension with w)",
          "Off by default unless prjfile is on") do |v|
    options[:worldfile] = v
  end
  
  opts.on("--[no-]prjfile", "Create .prj",
          "Off by default unless worldfile is on") do |v|
    options[:prjfile] = v
  end
  
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
  
end.parse!

options[:worldfile] = true if(options[:prjfile] && !options.include?(:worldfile))
options[:prjfile] = true if(options[:worldfile] && !options.include?(:prjfile))

DEFAULTS = {
  :semimajor=>"6378137.0 m".to_unit,
  :semiminor=>"6356752.3142 m".to_unit,
  :flattening=>298.257223563,
  :auxfile=>true,
  :worldfile=>false,
  :prjfile=>false
}

filename = ARGV[0]
raise OptionParser::MissingArgument, "FILE" if filename.nil?

if options.include? :flattening
  raise OptionParser::NeedlessArgument, "Can not specify both semi-minor axis and flattening" if options.include? :semiminor
  options[:semiminor] = options[:semimajor]*(1.0-1.0/options[:flattening])
elsif options.include? :semiminor
  raise OptionParser::MissingArgument, "Can not specify semi-minor axis without semi-major axis" unless options.include? :semimajor
  raise OptionParser::InvalidArgument, "Semi-minor axis must be less than semi-major axis" unless options[:semimajor]>options[:semiminor]
  options[:flattening] = (1.0*options[:semimajor]/(options[:semimajor]-options[:semiminor])).to_f
elsif options.include? :semimajor
  options[:flattening] = DEFAULTS[:flattening]
  options[:semiminor] = options[:semimajor]*(1.0-1.0/options[:flattening])
end


options = DEFAULTS.merge options

dim = Dimensions.dimensions(filename)
raise "Could not read #{ARGV[0]}" if dim.nil?

a=(options[:semimajor]*1.0>>"m").scalar
f=options[:flattening]
pixel_x = 360.0/dim[0]
pixel_y = -180.0/dim[1]

if options[:auxfile]
  open(filename+".aux.xml", 'w') do |file|
    file.puts <<EOS
<PAMDataset>
  <SRS>GEOGCS["unnamed ellipse",DATUM["unknown",SPHEROID["unnamed",#{a},#{f}]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]</SRS>
  <GeoTransform> -1.8000000000000000e+02,  #{pixel_x},  0.0000000000000000e+00,  9.0000000000000000e+01,  0.0000000000000000e+00, #{"%.7f"%pixel_y}</GeoTransform>
</PAMDataset>
EOS
  end
  puts "Wrote sidecar file #{ARGV[0]+".aux.xml"}"
end

if options[:worldfile]
  unless filename[-1]=='w'
    open(filename[0..-2]+"w", 'w') do |file|
      file.puts pixel_x
      file.puts 0.0
      file.puts 0.0
      file.puts pixel_y
      file.puts -180+pixel_x/2
      file.puts 90+pixel_y/2
    end
    puts "Wrote sidecar worldfile #{ARGV[0][0..-2]+"w"}"
  else
    puts "Could not write worldfile as #{ARGV[0]} already ends in 'w' and would be overwritten"
  end
end

if options[:prjfile]
  i = filename.rindex('.')
  if(i>=0)
    projfile = filename[0..i]+"prj"
  else
    projfile = filename+".prj"
  end
  open(projfile, 'w') do |file|
    file.puts <<EOS
GEOGCS["unnamed ellipse",DATUM["unknown",SPHEROID["unnamed",#{a.base_scalar},#{f}]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]
EOS
  end
  puts "Wrote projection sidecar file #{projfile}"
end

puts "Equatorial radius: #{(options[:semimajor]*1.0>>"m").to_s("%0.2f")} (#{options[:semimajor]*1.0>>"R_E"})"
puts "Polar radius: #{(options[:semiminor]*1.0>>"m").to_s("%0.2f")} (#{options[:semiminor]*1.0>>"R_E_P"})"
puts "Flattening: 1:#{f.to_f}"
