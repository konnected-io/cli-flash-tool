require 'rainbow'
require 'zebra/zpl'
require 'stringio'
require 'json'
require 'net/http'
require 'open-uri'
require 'active_support'
require 'active_support/core_ext'

Dir.glob(File.dirname(__FILE__) + '/lib/*') {|file| require file}

PreflightRunner.new.run