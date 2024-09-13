desc "Serve the documentation site"
task :serve_docs do
  begin
    Dir.chdir('docs') do
      unless system('bundle check')
        puts "Bundler is not installed or dependencies are not met. Please run 'bundle install'."
        exit 1
      end

      sh 'bundle exec jekyll s'
    end
  rescue Errno::ENOENT => e
    puts "Directory 'docs' not found: #{e.message}"
    exit 1
  rescue => e
    puts "An error occurred: #{e.message}"
    exit 1
  end
end
