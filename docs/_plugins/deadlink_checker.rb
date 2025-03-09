# frozen_string_literal: true

# _plugins/deadlink_checker.rb
require 'deadfinder'

Jekyll::Hooks.register :site, :post_write do |_site|
  puts 'Checking deadlinks after Jekyll build...'
  runner = DeadFinder::Runner.new
  options = runner.default_options
  options['concurrency'] = 30

  site_url = 'https://owasp-noir.github.io'
  DeadFinder.run_url(site_url, options)
  puts DeadFinder.output
end
