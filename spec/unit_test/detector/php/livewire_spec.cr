require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Livewire" do
  options = create_test_options
  instance = Detector::Php::Livewire.new options

  it "detects livewire/livewire and livewire/volt in composer.json" do
    instance.detect("composer.json", %({"require": {"livewire/livewire": "^3.5"}})).should be_true
    instance.detect("composer.json", %({"require": {"livewire/volt": "^1.6"}})).should be_true
  end

  it "detects a component class" do
    instance.detect("app/Livewire/EditPost.php", "<?php\nuse Livewire\\Component;\nclass EditPost extends Component {}").should be_true
    instance.detect("app/Livewire/EditPost.php", "<?php\nclass EditPost extends \\Livewire\\Component {}").should be_true
    instance.detect("resources/views/livewire/counter.blade.php", "<?php\nuse Livewire\\Volt\\Component;\nnew class extends Component {} ?>").should be_true
  end

  it "does not detect Blade view components or plain Laravel" do
    instance.detect("app/View/Components/Alert.php", "<?php\nuse Illuminate\\View\\Component;\nclass Alert extends Component {}").should be_false
    instance.detect("composer.json", %({"require": {"laravel/framework": "^11.0"}})).should be_false
  end
end
