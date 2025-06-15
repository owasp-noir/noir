require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/python/robyn" # Adjust path as necessary
require "../../../../src/analyzer/models/endpoint"        # Adjust path as necessary
require "../../../../src/analyzer/models/parameter"       # Adjust path as necessary
require "../../../../src/analyzer/models/details"         # Adjust path as necessary

describe "Functional Test for Python Robyn Analyzer" do
  @analyzer : Analyzer::Python::Robyn

  before_each do
    @analyzer = Analyzer::Python::Robyn.new
  end

  context "with 'simple_routes.py'" do
    it "should find all endpoints and their parameters correctly" do
      fixture_file = "spec/functional_test/fixtures/python/robyn/simple_routes.py"
      @analyzer.analyze(fixture_file)
      results = @analyzer.results

      results.size.should eq(4)

      # Endpoint 1: @app.get("/")
      endpoint1 = results[0]
      endpoint1.method.should eq("GET")
      endpoint1.path.should eq("/")
      endpoint1.details.is_a?(Models::Details).should be_true
      endpoint1.details.as(Models::Details).file_path.should eq(fixture_file)
      endpoint1.details.as(Models::Details).line.should eq(5) # Line of @app.get
      endpoint1.parameters.size.should eq(0) # 'request' is usually not listed as an API param

      # Endpoint 2: @app.post("/submit")
      endpoint2 = results[1]
      endpoint2.method.should eq("POST")
      endpoint2.path.should eq("/submit")
      endpoint2.details.as(Models::Details).line.should eq(9) # Line of @app.post
      endpoint2.parameters.size.should eq(0)

      # Endpoint 3: @app.put("/update/:item_id")
      endpoint3 = results[2]
      endpoint3.method.should eq("PUT")
      endpoint3.path.should eq("/update/:item_id")
      endpoint3.details.as(Models::Details).line.should eq(13) # Line of @app.put
      endpoint3.parameters.size.should eq(1)
      param3_1 = endpoint3.parameters[0]
      param3_1.name.should eq("item_id")
      param3_1.param_type.should eq("path")
      param3_1.required.should be_true # Path params are implicitly required
      # Robyn doesn't provide type info for path_params via request object in this style easily to static analysis

      # Endpoint 4: @app.delete("/item/:id")
      endpoint4 = results[3]
      endpoint4.method.should eq("DELETE")
      endpoint4.path.should eq("/item/:id")
      endpoint4.details.as(Models::Details).line.should eq(18) # Line of @app.delete
      endpoint4.parameters.size.should eq(1)
      param4_1 = endpoint4.parameters[0]
      param4_1.name.should eq("id")
      param4_1.param_type.should eq("path")
      param4_1.value_type.should eq("str")
      param4_1.required.should be_true
    end
  end

  context "with 'add_route_examples.py'" do
    it "should find all endpoints and their parameters correctly" do
      fixture_file = "spec/functional_test/fixtures/python/robyn/add_route_examples.py"
      @analyzer.analyze(fixture_file)
      results = @analyzer.results

      results.size.should eq(2)

      # Endpoint 1: app.add_route(method="GET", endpoint="/data", handler=handle_data)
      endpoint1 = results[0]
      endpoint1.method.should eq("GET")
      endpoint1.path.should eq("/data")
      endpoint1.details.as(Models::Details).file_path.should eq(fixture_file)
      endpoint1.details.as(Models::Details).line.should eq(11) # Line of app.add_route
      endpoint1.details.as(Models::Details).handler_function.should eq("handle_data")
      endpoint1.parameters.size.should eq(0)

      # Endpoint 2: app.add_route(method="POST", endpoint="/info/:info_id", handler=handle_info)
      endpoint2 = results[1]
      endpoint2.method.should eq("POST")
      endpoint2.path.should eq("/info/:info_id")
      endpoint2.details.as(Models::Details).line.should eq(12) # Line of app.add_route
      endpoint2.details.as(Models::Details).handler_function.should eq("handle_info")
      endpoint2.parameters.size.should eq(2)

      param2_1 = endpoint2.parameters.find { |p| p.name == "info_id" }.not_nil!
      param2_1.param_type.should eq("path")
      param2_1.value_type.should eq("int")
      param2_1.required.should be_true

      param2_2 = endpoint2.parameters.find { |p| p.name == "query_param" }.not_nil!
      param2_2.param_type.should eq("query")
      param2_2.value_type.should eq("str")
      param2_2.required.should be_false
      param2_2.default_value.should eq("\"default\"") # Or just "default" depending on parser
    end
  end

  context "with 'mixed_params.py'" do
    it "should find all endpoints and their parameters correctly" do
      fixture_file = "spec/functional_test/fixtures/python/robyn/mixed_params.py"
      @analyzer.analyze(fixture_file)
      results = @analyzer.results

      results.size.should eq(2)

      # Endpoint 1: @app.get("/search/:category")
      endpoint1 = results[0]
      endpoint1.method.should eq("GET")
      endpoint1.path.should eq("/search/:category")
      endpoint1.details.as(Models::Details).file_path.should eq(fixture_file)
      endpoint1.details.as(Models::Details).line.should eq(5) # Line of @app.get
      endpoint1.parameters.size.should eq(3)

      param1_1 = endpoint1.parameters.find { |p| p.name == "category" }.not_nil!
      param1_1.param_type.should eq("path")
      param1_1.value_type.should eq("str")
      param1_1.required.should be_true

      param1_2 = endpoint1.parameters.find { |p| p.name == "q" }.not_nil!
      param1_2.param_type.should eq("query")
      param1_2.value_type.should eq("str")
      param1_2.required.should be_true # No default value

      param1_3 = endpoint1.parameters.find { |p| p.name == "limit" }.not_nil!
      param1_3.param_type.should eq("query")
      param1_3.value_type.should eq("int")
      param1_3.required.should be_false
      param1_3.default_value.should eq("10")

      # Endpoint 2: @app.post(r"/raw/:data_point")
      endpoint2 = results[1]
      endpoint2.method.should eq("POST")
      endpoint2.path.should eq("/raw/:data_point") # Raw string r"" should be handled
      endpoint2.details.as(Models::Details).line.should eq(10) # Line of @app.post
      endpoint2.parameters.size.should eq(2)

      param2_1 = endpoint2.parameters.find { |p| p.name == "data_point" }.not_nil!
      param2_1.param_type.should eq("path")
      param2_1.value_type.should eq("str")
      param2_1.required.should be_true

      param2_2 = endpoint2.parameters.find { |p| p.name == "value" }.not_nil!
      param2_2.param_type.should eq("query")
      param2_2.value_type.should eq("float")
      param2_2.required.should be_true # No default value
    end
  end
end
