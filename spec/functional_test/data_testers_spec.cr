require "./func_spec"

# These types describe the fields FunctionalTester asserts. Reject unknown keys
# so a misspelled optional field can't quietly remove an assertion.
private struct DataTester
  include YAML::Serializable
  include YAML::Serializable::Strict

  @fixture : String
  @counts : Hash(String, Int32)
  @options : Hash(String, YAML::Any)?
  @endpoints : Array(ExpectedEndpoint)

  private struct ExpectedParam
    include YAML::Serializable
    include YAML::Serializable::Strict

    @name : String
    @type : String
    @value : String = ""

    def to_param
      Param.new(@name, @value, @type)
    end
  end

  private struct ExpectedCallee
    include YAML::Serializable
    include YAML::Serializable::Strict

    @name : String
    @path : String?
    @line : Int32?

    def to_callee
      Callee.new(@name, @path, @line)
    end
  end

  private struct ExpectedEndpoint
    include YAML::Serializable
    include YAML::Serializable::Strict

    @url : String
    @method : String
    @protocol : String = "http"
    @params : Array(ExpectedParam) = [] of ExpectedParam
    @callees : Array(ExpectedCallee) = [] of ExpectedCallee

    def to_endpoint
      endpoint = Endpoint.new(@url, @method, @params.map(&.to_param))
      endpoint.protocol = @protocol
      endpoint.callees = @callees.map(&.to_callee)
      endpoint
    end
  end

  COUNT_KEYS = {"techs" => :techs, "endpoints" => :endpoints}

  def perform_tests
    counts = @counts.transform_keys { |key| COUNT_KEYS[key] }
    FunctionalTester.new(@fixture, counts, @endpoints.map(&.to_endpoint), @options).perform_tests
  end

  def self.register(file)
    tester = File.open(file) { |io| from_yaml(io) }
    tester.perform_tests
  rescue ex
    raise Exception.new("Invalid functional tester #{file}: #{ex.message}", cause: ex)
  end
end

# Scoped just recipes pass either an individual YAML file or a language folder.
path = ENV["NOIR_SPEC_DATA_PATH"]? || "spec/functional_test/testers"
if File.directory?(path)
  Dir.glob(File.join(path, "**/*_spec.yml")).sort.each { |file| DataTester.register(file) }
else
  DataTester.register(path)
end
