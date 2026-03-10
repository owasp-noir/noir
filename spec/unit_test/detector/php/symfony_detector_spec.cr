require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Symfony" do
  options = create_test_options
  instance = Detector::Php::Symfony.new options

  it "detects composer.json with symfony/" do
    content = <<-JSON
      {
        "require": {
          "symfony/framework-bundle": "^6.4"
        }
      }
      JSON
    instance.detect("composer.json", content).should be_true
  end

  it "detects PHP file with use Symfony import" do
    content = <<-'PHP'
      <?php
      namespace App\Controller;
      use Symfony\Component\HttpFoundation\Response;

      class MyController {}
      PHP
    instance.detect("src/Controller/MyController.php", content).should be_true
  end

  it "detects one-line PHP open tag with Symfony import" do
    content = "<?php use Symfony\\Component\\HttpFoundation\\Response; class MyController {}"
    instance.detect("src/Controller/MyController.php", content).should be_true
  end

  it "detects config/bundles.php with Symfony\\" do
    content = <<-PHP
      <?php
      return [
          Symfony\\Bundle\\FrameworkBundle\\FrameworkBundle::class => ['all' => true],
      ];
      PHP
    instance.detect("config/bundles.php", content).should be_true
  end

  it "detects config/services.yaml with App\\" do
    content = <<-YAML
      services:
        App\\:
          resource: '../src/'
      YAML
    instance.detect("config/services.yaml", content).should be_true
  end

  it "detects src/Kernel.php with Symfony" do
    content = <<-'PHP'
      <?php
      namespace App;
      use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
      use Symfony\Component\HttpKernel\Kernel as BaseKernel;
      class Kernel extends BaseKernel { use MicroKernelTrait; }
      PHP
    instance.detect("src/Kernel.php", content).should be_true
  end

  it "detects public/index.php with Symfony" do
    content = <<-PHP
      <?php
      use App\\Kernel;
      require_once dirname(__DIR__).'/vendor/autoload_runtime.php';
      return function (array $context) {
          return new Kernel($context['APP_ENV'], (bool) $context['APP_DEBUG']);
      };
      PHP
    # public/index.php checks for "Symfony" in content; this file doesn't have it
    instance.detect("public/index.php", content).should be_false
  end

  it "detects public/index.php with Symfony in content" do
    content = "<?php\n// Symfony front controller\nuse App\\Kernel;\nrequire Symfony\\Runtime\\Autoloader;"
    instance.detect("public/index.php", content).should be_true
  end

  it "does not detect PHP test file with Symfony string literal only" do
    content = <<-PHP
      <?php
      namespace Tests\\Integration;
      use PHPUnit\\Framework\\TestCase;

      class TraceTest extends TestCase {
          public function testTrace(): void {
              $class = 'Symfony\\Bundle\\FrameworkBundle\\FrameworkBundle';
              $this->assertNotEmpty($class);
          }
      }
      PHP
    instance.detect("tests/integration/TraceTest.php", content).should be_false
  end

  it "does not detect PHP file with @Route but no Symfony import" do
    content = <<-'PHP'
      <?php
      namespace App\Controller;

      /** @Route("/home") */
      class HomeController {}
      PHP
    instance.detect("src/Controller/HomeController.php", content).should be_false
  end

  it "does not detect composer.json without symfony" do
    content = %({"name": "app", "require": {"php": "^8.0"}})
    instance.detect("composer.json", content).should be_false
  end

  it "does not detect non-PHP files" do
    instance.detect("index.html", "<html></html>").should be_false
    instance.detect("app.js", "console.log('hello')").should be_false
  end
end
