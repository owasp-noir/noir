namespace :docs do
  desc "Serve the documentation site"
  task :serve do
    within_docs_directory do
      unless system('bundle check')
        puts "Bundler is not installed or dependencies are not met. Please run 'rake docs:install'."
        exit 1
      end

      sh 'bundle exec jekyll s'
    end
  end

  desc "Install dependencies for the documentation site"
  task :install do
    within_docs_directory do
      sh 'bundle install'
    end
  end

  def within_docs_directory
    Dir.chdir('docs') do
      yield
    end
  rescue Errno::ENOENT => e
    puts "Directory 'docs' not found: #{e.message}"
    exit 1
  rescue => e
    puts "An error occurred: #{e.message}"
    exit 1
  end
end
