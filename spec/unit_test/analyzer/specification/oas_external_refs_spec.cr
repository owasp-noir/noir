require "file_utils"
require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/specification/oas2"
require "../../../../src/analyzer/analyzers/specification/oas3"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"
require "../../../../src/models/skipped_files"

# A `$ref` in the `paths` map points at another file, and until that is
# followed a split document yields nothing at all: the path strings are in the
# entry document, the operations are one file away. These specs pin the three
# limits that resolution runs under — local files only, contained inside the
# scan base, and terminating on a cycle — plus the promise that a ref noir
# will not follow costs only itself.

private def spec_options(base : String) : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  options
end

private def analyze_oas3(base : String, entry : String) : Array(Endpoint)
  CodeLocator.instance.clear_all
  CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, entry)
  Analyzer::Specification::Oas3.new(spec_options(base)).analyze
end

private def analyze_oas2(base : String, entry : String) : Array(Endpoint)
  CodeLocator.instance.clear_all
  CodeLocator.instance.push(Noir::LocatorKeys::SWAGGER_YAML, entry)
  Analyzer::Specification::Oas2.new(spec_options(base)).analyze
end

private def skip_messages : Array(String)
  Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).map(&.message)
end

private def with_temp_dir(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "OpenAPI external $ref resolution" do
  before_each { Noir::SkippedFiles.clear }
  after_each do
    Noir::SkippedFiles.clear
    CodeLocator.instance.clear_all
  end

  it "reads operations out of the file a path item refs" do
    with_temp_dir("noir_oas_split") do |dir|
      Dir.mkdir_p(File.join(dir, "paths"))
      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Split
          version: '1'
        paths:
          /pets:
            $ref: './paths/pets.yaml'
        components:
          parameters:
            Fields:
              name: fields
              in: query
              schema:
                type: string
        YAML
      File.write(File.join(dir, "paths", "pets.yaml"), <<-YAML)
        get:
          operationId: listPets
          parameters:
            - $ref: '../openapi.yaml#/components/parameters/Fields'
        YAML

      endpoints = analyze_oas3(dir, entry)

      endpoints.size.should eq(1)
      endpoints[0].method.should eq("GET")
      endpoints[0].url.should eq("/pets")
      # The fragment after the file name is followed too: declining it would
      # read the operation and lose every parameter it declares.
      endpoints[0].params.map(&.name).should contain("fields")
    end
  end

  it "refuses a ref that resolves outside the scan base" do
    with_temp_dir("noir_oas_escape") do |dir|
      project = File.join(dir, "project")
      Dir.mkdir_p(project)

      # A perfectly valid path item, and readable — only the containment rule
      # stands between it and the scan.
      File.write(File.join(dir, "secrets.yaml"), <<-YAML)
        get:
          operationId: leak
        YAML
      File.write(File.join(project, "inside.yaml"), <<-YAML)
        get:
          operationId: listPets
        YAML

      entry = File.join(project, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Escape
          version: '1'
        paths:
          /pets:
            $ref: './inside.yaml'
          /leak:
            $ref: '../secrets.yaml'
        YAML

      endpoints = analyze_oas3(project, entry)

      endpoints.map(&.url).should eq(["/pets"])
      skip_messages.join("\n").should contain("outside the scan base")
    end
  end

  it "does not follow a symlinked ref target" do
    with_temp_dir("noir_oas_symlink") do |dir|
      project = File.join(dir, "project")
      Dir.mkdir_p(project)

      File.write(File.join(dir, "secrets.yaml"), <<-YAML)
        get:
          operationId: leak
        YAML
      # The link itself sits inside the scan base, so the textual containment
      # check passes; only refusing to follow it keeps the scan in the tree.
      File.symlink(File.join(dir, "secrets.yaml"), File.join(project, "link.yaml"))
      File.write(File.join(project, "inside.yaml"), <<-YAML)
        get:
          operationId: listPets
        YAML

      entry = File.join(project, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Symlink
          version: '1'
        paths:
          /pets:
            $ref: './inside.yaml'
          /leak:
            $ref: './link.yaml'
        YAML

      endpoints = analyze_oas3(project, entry)

      endpoints.map(&.url).should eq(["/pets"])
      skip_messages.join("\n").should contain("symbolic link")
    end
  end

  it "does not fetch a remote ref" do
    with_temp_dir("noir_oas_remote") do |dir|
      File.write(File.join(dir, "inside.yaml"), <<-YAML)
        get:
          operationId: listPets
        YAML

      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Remote
          version: '1'
        paths:
          /pets:
            $ref: './inside.yaml'
          /remote:
            $ref: 'https://specs.example.com/paths/remote.yaml'
        YAML

      endpoints = analyze_oas3(dir, entry)

      endpoints.map(&.url).should eq(["/pets"])
      skip_messages.join("\n").should contain("remote target is not fetched")
    end
  end

  it "terminates on a cycle between two files" do
    with_temp_dir("noir_oas_cycle") do |dir|
      File.write(File.join(dir, "a.yaml"), "$ref: './b.yaml'\n")
      File.write(File.join(dir, "b.yaml"), "$ref: './a.yaml'\n")
      File.write(File.join(dir, "params.yaml"), <<-YAML)
        $ref: './params.yaml'
        YAML

      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Cycle
          version: '1'
        paths:
          /loop:
            $ref: './a.yaml'
          /pets:
            get:
              operationId: listPets
              parameters:
                - $ref: './params.yaml'
        YAML

      endpoints = analyze_oas3(dir, entry)

      # Reaching this line at all is the assertion: an unbroken cycle either
      # hangs or exhausts the stack.
      endpoints.map(&.url).should eq(["/pets"])
      endpoints[0].params.should be_empty
    end
  end

  it "keeps the paths it already read when a target is missing" do
    with_temp_dir("noir_oas_missing") do |dir|
      File.write(File.join(dir, "inside.yaml"), <<-YAML)
        get:
          operationId: listPets
        YAML

      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.1
        info:
          title: Missing
          version: '1'
        paths:
          /gone:
            $ref: './nowhere.yaml'
          /pets:
            $ref: './inside.yaml'
        YAML

      endpoints = analyze_oas3(dir, entry)

      endpoints.map(&.url).should eq(["/pets"])
      messages = skip_messages.join("\n")
      messages.should contain("./nowhere.yaml")
      messages.should contain("target not found")
    end
  end

  it "resolves a split Swagger 2.0 document the same way" do
    with_temp_dir("noir_oas2_split") do |dir|
      Dir.mkdir_p(File.join(dir, "paths"))
      entry = File.join(dir, "swagger.yaml")
      File.write(entry, <<-YAML)
        swagger: '2.0'
        info:
          title: Split
          version: '1'
        basePath: /v1
        paths:
          /pets:
            $ref: './paths/pets.yaml'
        parameters:
          Fields:
            name: fields
            in: query
            type: string
        YAML
      File.write(File.join(dir, "paths", "pets.yaml"), <<-YAML)
        get:
          operationId: listPets
          parameters:
            - $ref: '../swagger.yaml#/parameters/Fields'
        YAML

      endpoints = analyze_oas2(dir, entry)

      endpoints.size.should eq(1)
      endpoints[0].url.should eq("/v1/pets")
      endpoints[0].params.map(&.name).should contain("fields")
    end
  end
end
