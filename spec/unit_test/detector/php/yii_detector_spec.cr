require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Yii2" do
  options = create_test_options
  instance = Detector::Php::Yii.new options

  it "detects composer.json with yiisoft/yii2" do
    content = <<-JSON
      {
        "require": {
          "yiisoft/yii2": "~2.0.45"
        }
      }
      JSON
    instance.detect("composer.json", content).should be_true
  end

  it "detects PHP file with use yii\\ import" do
    content = <<-'PHP'
      <?php
      namespace app\controllers;
      use yii\web\Controller;

      class SiteController extends Controller {}
      PHP
    instance.detect("controllers/SiteController.php", content).should be_true
  end

  it "detects one-line PHP open tag with use Yii import" do
    content = "<?php use Yii; class MyClass {}"
    instance.detect("src/MyClass.php", content).should be_true
  end

  it "detects controller extending yii\\web\\Controller" do
    content = <<-'PHP'
      <?php
      namespace app\controllers;

      class PostController extends \yii\web\Controller {}
      PHP
    instance.detect("controllers/PostController.php", content).should be_true
  end

  it "detects controller extending yii\\rest\\ActiveController" do
    content = <<-'PHP'
      <?php
      namespace app\controllers;

      class UserController extends yii\rest\ActiveController
      {
          public $modelClass = 'app\models\User';
      }
      PHP
    instance.detect("controllers/UserController.php", content).should be_true
  end

  it "detects files under vendor/yiisoft/ path" do
    instance.detect("vendor/yiisoft/yii2/base/Component.php", "<?php").should be_true
  end

  it "detects Yii.php bootstrap file" do
    content = <<-PHP
      <?php
      class Yii extends \\yii\\BaseYii {}
      PHP
    instance.detect("Yii.php", content).should be_true
  end

  it "does not detect composer.json without yiisoft/yii2" do
    content = %({"name": "app", "require": {"php": "^8.0"}})
    instance.detect("composer.json", content).should be_false
  end

  it "does not detect PHP file without Yii import" do
    content = <<-'PHP'
      <?php
      namespace App\Controller;

      class RandomController {}
      PHP
    instance.detect("src/Controller/RandomController.php", content).should be_false
  end

  it "does not detect non-PHP files" do
    instance.detect("index.html", "<html></html>").should be_false
    instance.detect("app.js", "console.log('hello')").should be_false
  end
end
