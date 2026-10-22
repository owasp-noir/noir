require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Frappe" do
  options = create_test_options
  instance = Detector::Python::Frappe.new options

  it "import frappe" do
    instance.detect("library_app/api.py", "import frappe").should be_true
  end

  it "from frappe.model.document import" do
    instance.detect("book.py", "from frappe.model.document import Document").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# ported from frappe import helpers\nimport flask").should be_false
  end

  it "non-python extension" do
    instance.detect("api.txt", "import frappe").should be_false
  end
end
