# frozen_string_literal: true

# _plugins/deadlink_checker.rb
require 'deadfinder'

Jekyll::Hooks.register :site, :post_write do |_site|
  jekyll_env = ENV['JEKYLL_ENV'] || 'development'
  
  if jekyll_env != 'production'
    puts 'Checking deadlinks after Jekyll build...'
    runner = DeadFinder::Runner.new
    options = runner.default_options
    options['concurrency'] = 30

    site_url = ENV['JEKYLL_SITE_URL'] || 'http://127.0.0.1:4000'
    begin
      DeadFinder.run_url(site_url, options)
      if DeadFinder.output.empty?
        puts 'No deadlinks found!'
      else
        DeadFinder.output.each do |key, value|
          puts "#{key}: #{value}" if value && !value.empty?
        end
      end
    rescue StandardError => e
      puts "Deadlink checker failed: #{e.message}"
    end
  else
    puts 'Skipping deadlink check in production environment'
  end
end
