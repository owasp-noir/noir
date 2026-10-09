require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Laravel Folio" do
  options = create_test_options
  instance = Detector::Php::Folio.new options

  it "detects laravel/folio in composer.json" do
    instance.detect("composer.json", %({"require": {"laravel/folio": "^1.1"}})).should be_true
  end

  it "detects a Folio mount and a Folio page" do
    instance.detect("app/Providers/FolioServiceProvider.php", "<?php\nFolio::path(resource_path('views/pages'));").should be_true
    instance.detect("resources/views/pages/index.blade.php", "<?php\nuse function Laravel\\Folio\\{middleware};\nmiddleware(['auth']); ?>").should be_true
  end

  it "does not detect plain Laravel" do
    instance.detect("composer.json", %({"require": {"laravel/framework": "^11.0"}})).should be_false
    instance.detect("routes/web.php", "<?php\nRoute::get('/portfolio', fn () => view('portfolio'));").should be_false
  end
end
