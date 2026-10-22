require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Odoo" do
  options = create_test_options
  instance = Detector::Python::Odoo.new options

  it "from odoo import http" do
    instance.detect("controllers/main.py", "from odoo import http").should be_true
  end

  it "from odoo.http import route" do
    instance.detect("controllers/rpc.py", "from odoo.http import Controller, route").should be_true
  end

  it "from odoo.addons import" do
    instance.detect("controllers/main.py", "from odoo.addons.website.controllers.main import Website").should be_true
  end

  it "legacy openerp import" do
    instance.detect("controllers.py", "from openerp import http").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# migrated from odoo import scripts\nimport flask").should be_false
  end

  it "non-python extension" do
    instance.detect("main.txt", "from odoo import http").should be_false
  end
end
