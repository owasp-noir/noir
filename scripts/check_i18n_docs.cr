#!/usr/bin/env crystal
# noir/scripts/check_i18n_docs.cr
# Check for missing i18n (Korean) documentation files
# Compares index.md/_index.md files with their corresponding .ko.md versions
# Usage: crystal run scripts/check_i18n_docs.cr
# Usage: just docs-i18n-check

require "file_utils"

class I18nDocsChecker
  def initialize(@base_path : String = "docs/content")
  end

  def check_missing_ko_docs
    puts "Checking for missing Korean (ko) documentation files..."
    puts "Base path: #{@base_path}"
    puts

    missing_files = [] of String
    total_files = 0

    # Find all index.md and _index.md files
    index_files = find_index_files(@base_path)
    
    index_files.each do |file_path|
      total_files += 1
      ko_file_path = get_ko_file_path(file_path)
      
      unless File.exists?(ko_file_path)
        missing_files << ko_file_path
        puts "❌ Missing: #{ko_file_path}"
      else
        puts "✅ Found: #{ko_file_path}"
      end
    end

    puts
    puts "Summary:"
    puts "  Total documentation files: #{total_files}"
    puts "  Missing Korean translations: #{missing_files.size}"
    
    if missing_files.empty?
      puts "  🎉 All documentation files have Korean translations!"
    else
      puts "  📝 Files needing Korean translation:"
      missing_files.each do |file|
        puts "    - #{file}"
      end
    end

    # Return exit code based on whether there are missing files
    missing_files.empty? ? 0 : 1
  end

  private def find_index_files(base_path : String) : Array(String)
    files = [] of String
    
    unless Dir.exists?(base_path)
      puts "Warning: Documentation directory '#{base_path}' does not exist."
      return files
    end
    
    Dir.glob("#{base_path}/**/index.md").each { |f| files << f }
    Dir.glob("#{base_path}/**/_index.md").each { |f| files << f }
    
    files.sort
  end

  private def get_ko_file_path(original_path : String) : String
    # Convert index.md to index.ko.md
    # Convert _index.md to _index.ko.md
    if original_path.ends_with?("index.md")
      original_path.sub(/index\.md$/, "index.ko.md")
    elsif original_path.ends_with?("_index.md")
      original_path.sub(/_index\.md$/, "_index.ko.md")
    else
      # Should not happen with our glob patterns, but just in case
      original_path.sub(/\.md$/, ".ko.md")
    end
  end
end

# Run the checker
checker = I18nDocsChecker.new
exit_code = checker.check_missing_ko_docs
exit(exit_code)