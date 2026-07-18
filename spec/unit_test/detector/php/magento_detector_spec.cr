require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Magento" do
  options = create_test_options
  instance = Detector::Php::Magento.new options

  it "detects Magento from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "magento/product-community-edition": "2.4.6"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Magento from registration.php" do
    reg_content = <<-'PHP'
      <?php
      use Magento\Framework\Component\ComponentRegistrar;
      ComponentRegistrar::register(ComponentRegistrar::MODULE, 'Acme_Blog', __DIR__);
      PHP
    instance.detect("app/code/Acme/Blog/registration.php", reg_content).should be_true
  end

  it "detects Magento from webapi.xml" do
    webapi_content = <<-'XML'
      <?xml version="1.0"?>
      <routes>
        <route url="/V1/products/:sku" method="GET">
          <service class="Magento\Catalog\Api\ProductRepositoryInterface" method="get"/>
        </route>
      </routes>
      XML
    instance.detect("app/code/Acme/Blog/etc/webapi.xml", webapi_content).should be_true
  end

  it "detects Magento from routes.xml" do
    routes_content = <<-XML
      <?xml version="1.0"?>
      <config>
        <router id="standard">
          <route id="blog" frontName="blog">
            <module name="Acme_Blog"/>
          </route>
        </router>
      </config>
      XML
    instance.detect("app/code/Acme/Blog/etc/frontend/routes.xml", routes_content).should be_true
  end

  it "detects Magento from the Magento namespace in PHP" do
    controller_content = <<-'PHP'
      <?php
      namespace Acme\Blog\Controller\Index;
      use Magento\Framework\App\Action\HttpGetActionInterface;
      class Index implements HttpGetActionInterface {}
      PHP
    instance.detect("Controller/Index/Index.php", controller_content).should be_true
  end

  it "does not detect Magento from unrelated files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("routes.xml", "<routes><get path='/x'/></routes>").should_not be_true
    instance.detect("composer.json", %({"require": {"laravel/framework": "^10.0"}})).should_not be_true
  end
end
