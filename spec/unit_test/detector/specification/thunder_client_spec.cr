require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Thunder Client Collection" do
  options = create_test_options
  instance = Detector::Specification::ThunderClient.new options
  locator = CodeLocator.instance

  legacy = %([{"_id": "1", "name": "List", "url": "{{baseUrl}}/users", "method": "GET"}])
  collection = %({"_id": "c1", "colName": "Orders", "folders": [], "requests": #{legacy}})

  it "detects and registers the legacy thunderclient.json" do
    locator.clear Noir::LocatorKeys::THUNDER_CLIENT_JSON
    instance.detect("app/thunder-tests/thunderclient.json", legacy).should be_true
    locator.all(Noir::LocatorKeys::THUNDER_CLIENT_JSON).should eq(["app/thunder-tests/thunderclient.json"])
  end

  it "detects a per-collection file" do
    instance.detect("thunder-tests/collections/tc_col_orders.json", collection).should be_true
  end

  it "ignores files outside thunder-tests/" do
    instance.detect("config/requests.json", legacy).should be_false
  end

  it "ignores metadata files without requests" do
    meta = %([{"_id": "c1", "colName": "Users", "folders": [], "settings": {"url": "x"}}])
    instance.detect("thunder-tests/thunderCollection.json", meta).should be_false
  end
end
