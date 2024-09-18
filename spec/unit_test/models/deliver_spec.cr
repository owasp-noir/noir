require "../../../src/models/deliver.cr"
require "../../../src/options.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  options["send_proxy"] = YAML::Any.new("http://localhost:8090")
  options["nolog"] = YAML::Any.new(true)

  it "Deliver" do
    object = Deliver.new options
    object.proxy.should eq("http://localhost:8090")
  end

  it "Deliver with headers" do
    options["send_with_headers"] = YAML::Any.new([YAML::Any.new("X-API-Key: abcdssss")])
    object = Deliver.new options
    object.headers["X-API-Key"].should eq("abcdssss")
  end

  it "Deliver with headers (bearer case)" do
    options["send_with_headers"] = YAML::Any.new([YAML::Any.new("Authorization: Bearer gAAAAABl3qwaQqol243Np")])
    object = Deliver.new options
    object.headers["Authorization"].should eq("Bearer gAAAAABl3qwaQqol243Np")
  end

  it "Deliver with matchers" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.matchers[0].to_s.should eq("/admin")
  end

  it "Deliver with filters" do
    options["use_filters"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.filters[0].to_s.should eq("/admin")
  end
end
