require "../../../models/detector"
require "json"

module Detector::Php
  class Laravel < Detector
    def detect(filename : String, file_contents : String) : Bool
      # This detector primarily works by checking directory structure and specific files,
      # so filename and file_contents might not be directly used if we have access to the project root.
      # However, 'filename' could be composer.json, so we can check its content.

      # Check for composer.json and its content
      if filename.ends_with?("composer.json")
        begin
          json = JSON.parse(file_contents)
          if json.is_a?(Hash) && json["require"]?.try(&.as_h).try(&.has_key?("laravel/framework"))
            @name = "php_laravel" # Set name early if composer.json confirms
            return true
          end
        rescue ex : JSON::ParseException
          # Ignore if composer.json is invalid
        end
      end

      # Fallback/alternative checks if not determined by composer.json alone,
      # assuming we can check file existence from a base path.
      # These checks are more suited if the detector is called with the project's root path.
      # For now, we'll rely on the project scanner to call this detector appropriately.
      # A more robust approach would be to have the main detector logic pass the base_path
      # and a list of all files, or provide a way to check file existence.

      # Placeholder for direct file/directory checks if the main tool supports it for detectors
      # e.g. File.exists?(File.join(@base_path, "artisan"))
      # e.g. Dir.exists?(File.join(@base_path, "app/Http/Controllers"))
      # e.g. File.exists?(File.join(@base_path, "routes/web.php"))

      # If the above checks are not conclusive or not performed here,
      # the name might not be set yet or might be the default.
      # The primary detection for Laravel often relies on composer.json content
      # or the presence of the 'artisan' script.

      false # Default to false if specific Laravel markers are not found by this method alone
    end

    def set_name
      # Name can also be set here if a global project scan confirms it's Laravel
      # For now, we rely on detection during the 'detect' method or a specific call for Laravel.
      @name = "php_laravel"
    end

    # We might need a way to signal that this detector needs to inspect specific files
    # like composer.json or be aware of the project structure.
    # For now, this basic structure follows the php_pure example.
    # A more advanced detector might be initialized with the project's root directory.

    # This method will be called by the main detector logic if it iterates through files.
    # To make this detector effective, the main detector should ideally feed it composer.json's content,
    # or the detector needs access to the file system relative to the project root.
    # Let's assume the main detector will try to match this detector against composer.json
    def check_laravel_project(project_root : String) : Bool
      # Check for artisan file
      return false unless File.exists?(File.join(project_root, "artisan"))

      # Check for composer.json and its content
      composer_path = File.join(project_root, "composer.json")
      return false unless File.exists?(composer_path)

      begin
        composer_content = File.read(composer_path)
        json = JSON.parse(composer_content)
        if json.is_a?(Hash) && json["require"]?.try(&.as_h).try(&.has_key?("laravel/framework"))
          # Characteristic directories (optional, but good indicators)
          return false unless Dir.exists?(File.join(project_root, "app/Http/Controllers"))
          return false unless Dir.exists?(File.join(project_root, "routes")) # web.php or api.php would be inside
          return true
        end
      rescue ex
        # JSON parse error or file read error
        return false
      end

      false
    end

    # The 'detect' method provided by the base class is generic.
    # We might need to override how this detector is invoked or how it gets its data.
    # For a framework detector, it's often about the project structure, not a single file's content.
    # Let's refine the 'detect' method to be more practical if it's called with a filename from the root.
    # If filename is "artisan" or "composer.json" from the root, it's a good sign.
    # This is a simplified approach. A full project scan context would be better.
    #
    # Revising the detect method to be more aligned with how detectors seem to be used (per file):
    # The challenge is that a single file doesn't define a Laravel project.
    # The `php_pure` detector checks `<?php` in *any* .php file.
    # For Laravel, we need a broader check.
    #
    # Let's assume the main `Detector` class in `src/detector/detector.cr` will have a list of
    # language-specific detectors and then framework-specific ones.
    # It might first detect PHP, then try Laravel.
    #
    # A simple heuristic for the `detect` method if called for each file:
    # If we encounter 'composer.json' and it has 'laravel/framework', it's Laravel.
    # If we encounter 'artisan', it's very likely Laravel.
    #
    # The `check_laravel_project` is a more holistic check if the detector runner can use it.
    # For now, `detect` will focus on `composer.json`.
    # The `set_name` will set the name.
  end
end

# The following is a more standard implementation based on the existing Detector model:
# The main detector loop will iterate over files. If it finds composer.json, it can use this.
module Detector::Php
  class LaravelDetector < Detector # Renaming to avoid conflict if class 'Laravel' is too generic
    def initialize(options = {} of String => String)
      super(options)
      set_name
    end

    # This method is called for each file by the DetectorRunner
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?("composer.json")
        begin
          json = JSON.parse(file_contents)
          if json.is_a?(Hash)
            # Check direct dependencies
            if json["require"]?.try(&.as_h).try(&.has_key?("laravel/framework"))
              return true
            end
            # Check dev dependencies (less likely for framework itself, but good to cover)
            if json["require-dev"]?.try(&.as_h).try(&.has_key?("laravel/framework"))
              return true
            end
          end
        rescue ex : JSON::ParseException
          # logger.debug "Failed to parse composer.json: #{ex.message}"
          return false # Invalid JSON is not a Laravel project indicator
        end
      end

      # A simple check for the artisan script.
      # This assumes the filename is the path relative to the project root.
      if filename == "artisan" || filename.ends_with?("/artisan")
        # Check if it's an executable or contains typical artisan script content
        # For simplicity, just its presence is a strong hint.
        # A more robust check would be to see if it contains "Illuminate\Foundation\Application"
        if file_contents.includes?("Illuminate\\Foundation\\Application")
          return true
        end
      end

      false
    end

    def set_name
      @name = "php_laravel"
    end

    # This method could be called by a higher-level detection logic that has access to the project root.
    def project_level_detect(project_root_path : String) : Bool
      artisan_path = File.join(project_root_path, "artisan")
      composer_json_path = File.join(project_root_path, "composer.json")

      unless File.exists?(artisan_path)
        return false
      end

      unless File.exists?(composer_json_path)
        return false
      end

      begin
        composer_content = File.read(composer_json_path)
        json = JSON.parse(composer_content)
        if json.is_a?(Hash) && json["require"]?.try(&.as_h).try(&.has_key?("laravel/framework"))
          # Optionally, check for characteristic directories for higher confidence
          # if Dir.exists?(File.join(project_root_path, "app/Http/Controllers")) &&
          #    Dir.exists?(File.join(project_root_path, "routes"))
          #   return true
          # end
          return true
        end
      rescue ex
        # logger.debug "Error during Laravel project-level detection: #{ex.message}"
        return false
      end

      false
    end
  end
end
