require "../../../spec_helper"
require "../../../../src/detector/detectors/php/laravel" # Adjust path if needed
require "../../../../src/models/detector"       # Ensure base Detector class is loaded

describe Detector::Php::LaravelDetector do
  options = {} of String => String # Mock options if your detector uses them

  it "should correctly set the name" do
    detector = Detector::Php::LaravelDetector.new(options)
    detector.name.should eq "php_laravel"
  end

  describe "#detect" do
    let(detector) { Detector::Php::LaravelDetector.new(options) }

    it "should detect laravel from composer.json with laravel/framework" do
      composer_content = %({"require": {"laravel/framework": "^10.0"}})
      detector.detect("composer.json", composer_content).should be_true
    end

    it "should detect laravel from composer.json with laravel/framework in require-dev" do
      composer_content = %({"require-dev": {"laravel/framework": "^10.0"}})
      detector.detect("composer.json", composer_content).should be_true
    end

    it "should not detect laravel from composer.json without laravel/framework" do
      composer_content = %({"require": {"another/package": "^1.0"}})
      detector.detect("composer.json", composer_content).should be_false
    end

    it "should not detect laravel from an empty composer.json" do
      composer_content = %({})
      detector.detect("composer.json", composer_content).should be_false
    end

    it "should not detect laravel from invalid composer.json" do
      composer_content = %({invalid json content})
      detector.detect("composer.json", composer_content).should be_false
    end

    it "should detect laravel from artisan file with specific content" do
      artisan_content = <<-ARTISAN_SCRIPT
        #!/usr/bin/env php
        <?php
        define('LARAVEL_START', microtime(true));
        require __DIR__.'/../vendor/autoload.php';
        $app = require_once __DIR__.'/../bootstrap/app.php';
        $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
        $status = $kernel->handle(
            $input = new Symfony\Component\Console\Input\ArgvInput,
            new Symfony\Component\Console\Output\ConsoleOutput
        );
        exit($status);
        ARTISAN_SCRIPT
      detector.detect("artisan", artisan_content).should be_true
    end

    it "should detect laravel from artisan file (alternative path) with specific content" do
      artisan_content = "require 'Illuminate\Foundation\Application';" # Simplified check
      detector.detect("path/to/artisan", artisan_content).should be_true
    end

    it "should not detect laravel from an empty artisan file" do
      detector.detect("artisan", "").should be_false
    end

    it "should not detect laravel from an artisan file with unrelated content" do
      artisan_content = "echo 'hello world';"
      detector.detect("artisan", artisan_content).should be_false
    end

    it "should not detect laravel from a generic php file" do
      php_content = "<?php echo 'hello';"
      detector.detect("index.php", php_content).should be_false
    end

    it "should not detect laravel from a non-relevant file" do
      other_content = "some text data"
      detector.detect("README.md", other_content).should be_false
    end
  end

  describe "#project_level_detect" do
    let(detector) { Detector::Php::LaravelDetector.new(options) }
    let(temp_dir) { Dir.mktmpdir("laravel_test") }

    after do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "should detect a valid Laravel project structure" do
      File.write(File.join(temp_dir, "artisan"), "Illuminate\Foundation\Application")
      File.write(File.join(temp_dir, "composer.json"), %({"require": {"laravel/framework": "10.0"}}))
      Dir.mkdir(File.join(temp_dir, "app"))
      Dir.mkdir(File.join(temp_dir, "app/Http"))
      Dir.mkdir(File.join(temp_dir, "app/Http/Controllers"))
      Dir.mkdir(File.join(temp_dir, "routes"))
      File.write(File.join(temp_dir, "routes/web.php"), "<?php // routes")

      detector.project_level_detect(temp_dir).should be_true
    end

    it "should not detect if artisan file is missing" do
      File.write(File.join(temp_dir, "composer.json"), %({"require": {"laravel/framework": "10.0"}}))
      detector.project_level_detect(temp_dir).should be_false
    end

    it "should not detect if composer.json file is missing" do
      File.write(File.join(temp_dir, "artisan"), "Illuminate\Foundation\Application")
      detector.project_level_detect(temp_dir).should be_false
    end

    it "should not detect if composer.json does not contain laravel/framework" do
      File.write(File.join(temp_dir, "artisan"), "Illuminate\Foundation\Application")
      File.write(File.join(temp_dir, "composer.json"), %({"require": {"other/package": "1.0"}}))
      detector.project_level_detect(temp_dir).should be_false
    end

    it "should handle errors when composer.json is unreadable or invalid in project_level_detect" do
      File.write(File.join(temp_dir, "artisan"), "Illuminate\Foundation\Application")
      File.write(File.join(temp_dir, "composer.json"), %({broken json"")))
      # This test primarily ensures it doesn't crash and returns false.
      # Logging of the error is handled within the method itself.
      detector.project_level_detect(temp_dir).should be_false
    end
  end
end
