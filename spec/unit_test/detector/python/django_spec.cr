require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Django" do
  options = create_test_options
  instance = Detector::Python::Django.new options

  it "settings.py" do
    instance.detect("settings.py", "from django.apps import AppConfig").should be_true
  end

  it "import django" do
    instance.detect("manage.py", "import django").should be_true
  end

  # Django REST Framework is a Django-only library, and a DRF app module
  # routinely imports nothing else: a `urls.py` that builds a router and
  # publishes `router.urls` is a complete Django URLconf with no `django`
  # import in it. Without these the app detected as nothing at all and its
  # entire REST surface was invisible.
  it "urls.py that only imports rest_framework" do
    instance.detect("urls.py", "from rest_framework.routers import DefaultRouter").should be_true
  end

  it "views.py that only imports rest_framework" do
    instance.detect("views.py", "from rest_framework import viewsets").should be_true
  end

  it "plain `import rest_framework`" do
    instance.detect("views.py", "import rest_framework").should be_true
  end

  # `rest_framework` has to be the imported module, not a substring of one.
  it "ignores a lookalike package name" do
    instance.detect("views.py", "from rest_framework_ext import helpers").should be_false
  end

  it "ignores a non-Django python file" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end
end
