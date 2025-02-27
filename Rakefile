# frozen_string_literal: true

namespace :docs do
  desc 'Serve the documentation site'
  task :serve do
    within_docs_directory do
      unless system('bundle check')
        puts "Bundler is not installed or dependencies are not met. Please run 'rake docs:install'."
        exit 1
      end

      sh 'bundle exec jekyll s'
    end
  end

  desc 'Install dependencies for the documentation site'
  task :install do
    within_docs_directory do
      sh 'bundle install'
    end
  end

  desc 'Generate usage documentation'
  task :generate_usage do
    output = `./bin/noir --help-all`
    cleaned_output = output.gsub(/\e\[[0-9;]*m/, '') # Remove ANSI color codes
    File.write('docs/_includes/usage.md', cleaned_output)
  end

  def within_docs_directory(&block)
    Dir.chdir('docs', &block)
  rescue Errno::ENOENT => e
    puts "Directory 'docs' not found: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "An error occurred: #{e.message}"
    exit 1
  end
end

namespace :lint do
  desc 'Format the code using crystal tool format'
  task :format do
    sh 'crystal tool format'
  end

  desc 'Lint the code using ameba'
  task :ameba do
    sh 'ameba --fix'
  end

  desc 'Run all linting tasks'
  task all: %i[format ameba]
end

namespace :completion do
  desc 'Check for missing flags in completion scripts'
  task :check do
    # Extract flags from ./bin/noir -h
    noir_help_output = `./bin/noir -h`
    noir_flags = noir_help_output.scan(/^\s+(-\w|--\w[\w-]*)/).flatten.uniq

    # Generate completion scripts
    zsh_completion = `./bin/noir --generate-completion=zsh`
    bash_completion = `./bin/noir --generate-completion=bash`
    fish_completion = `./bin/noir --generate-completion=fish`

    # Extract flags from generated completion scripts
    completion_scripts = {
      'zsh' => zsh_completion,
      'bash' => bash_completion,
      'fish' => fish_completion
    }

    completion_scripts.each do |shell, content|
      missing_flags = noir_flags.reject { |flag| content.include?(flag) }

      if missing_flags.empty?
        puts "All flags are present in the #{shell} completion script."
      else
        puts "Missing flags in #{shell} completion script:"
        missing_flags.each { |flag| puts flag }
      end
    end
  end
end
