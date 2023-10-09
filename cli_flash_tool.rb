require 'rainbow'
require 'zebra/zpl'
require 'stringio'

Dir.glob(File.dirname(__FILE__) + '/lib/*') {|file| require file}

puts "OK!"
PreflightRunner.new.run