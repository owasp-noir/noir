require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Mautic" do
  options = create_test_options
  instance = Detector::Php::Mautic.new options

  it "detects Mautic from composer.json core-lib require" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "mautic/core-lib": "^5.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects a Mautic bundle route config" do
    php_content = <<-'PHP'
      <?php
      return [
          'routes' => [
              'main' => [
                  'mautic_x' => ['path' => '/x', 'controller' => 'Mautic\CoreBundle\Controller\XController::indexAction'],
              ],
          ],
      ];
      PHP
    instance.detect("app/bundles/CoreBundle/Config/config.php", php_content).should be_true
  end

  it "does not detect unrelated PHP projects" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("composer.json", %({"require": {"symfony/framework-bundle": "^6.0"}})).should_not be_true
    # A plain Symfony config.php with a 'routes' array but no Mautic controllers
    instance.detect("config/routes.php", %(<?php return ['routes' => []];)).should_not be_true
  end
end
