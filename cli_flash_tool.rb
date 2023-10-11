require 'rainbow'
require 'zebra/zpl'
require 'stringio'
require 'active_support'
require 'active_support/core_ext'

Dir.glob(File.dirname(__FILE__) + '/lib/*') {|file| require file}

PreflightRunner.new.run