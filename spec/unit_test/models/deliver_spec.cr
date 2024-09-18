require "../../../src/models/deliver.cr"
require "../../../src/options.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = "noir"
  options["send_proxy"] = "http://localhost:8090"
  options["nolog"] = true

  it "Deliver" do
    object = Deliver.new options
    object.proxy.should eq("http://localhost:8090")
  end

  it "Deliver with headers" do
    options["send_with_headers"] = "X-API-Key: abcdssss"
    object = Deliver.new options
    object.headers["X-API-Key"].should eq("abcdssss")
  end

  it "Deliver with headers (bearer case)" do
    options["send_with_headers"] = "Authorization: Bearer gAAAAABl3qwaQqol243Np"
    object = Deliver.new options
    object.headers["Authorization"].should eq("Bearer gAAAAABl3qwaQqol243Np")
  end

  it "Deliver with matchers" do
    options["use_matchers"] = "/admin"
    object = Deliver.new options
    object.matchers.should eq(["/admin"])
  end

  it "Deliver with filters" do
    options["use_filters"] = "/admin"
    object = Deliver.new options
    object.filters.should eq(["/admin"])
  end
end
