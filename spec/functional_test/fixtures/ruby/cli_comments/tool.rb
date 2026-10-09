#!/usr/bin/env ruby
require 'optparse'

OptionParser.new do |opts|
  # opts.on("--old-flag", "removed in 2.0")
  opts.on("--real", "the live option") # opts.on("--trailing")
end.parse!

=begin
ENV['DOC_ONLY_VAR'] was the old knob.
=end

ENV['SET_ONLY'] = 'x'
token = ENV['READ_ME']
ENV['DEFAULTED'] ||= 'y'
