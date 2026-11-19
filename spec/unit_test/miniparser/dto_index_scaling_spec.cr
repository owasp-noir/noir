require "../../spec_helper"
require "file_utils"
require "../../../src/models/logger"
require "../../../src/miniparsers/java_parameter_extractor_ts"
require "../../../src/miniparsers/kotlin_parameter_extractor_ts"

# One package of `n` controllers, each with its own DTO. Returns the time
# to build the DTO index of every controller, and the field names one
# controller sees for its DTO.
private def index_package(n : Int32, kotlin : Bool) : {Time::Span, Array(String)}
  tmp = File.tempname("noir-dto-scaling")
  dir = File.join(tmp, "src/main/#{kotlin ? "kotlin" : "java"}/com/acme")
  Dir.mkdir_p(dir)
  controllers = (0...n).map do |i|
    if kotlin
      path = File.join(dir, "C#{i}.kt")
      File.write(path, "package com.acme\ndata class D#{i}(val a: String, val b: Int)\nclass C#{i} { fun save(d: D#{i}) = \"x\" }\n")
    else
      path = File.join(dir, "C#{i}.java")
      File.write(path, "package com.acme;\npublic class C#{i} { public String save(D#{i} d) { return \"x\"; } }\n")
      File.write(File.join(dir, "D#{i}.java"), "package com.acme;\npublic class D#{i} { public String a; public int b; }\n")
    end
    {path, File.read(path)}
  end

  fields = [] of String
  elapsed = Time.measure do
    if kotlin
      builder = Noir::TreeSitterKotlinDtoIndex.new
      controllers.each_with_index do |(path, content), i|
        index = builder.build_for(path, content)
        fields = index["D#{i}"].map(&.name) if i == 1
      end
    else
      builder = Noir::TreeSitterJavaDtoIndex.new
      controllers.each_with_index do |(path, content), i|
        index = builder.build_for(path, content)
        fields = index["D#{i}"].map(&.name) if i == 1
      end
    end
  end
  {elapsed, fields}
ensure
  FileUtils.rm_rf(tmp) if tmp
  Noir::TreeSitterJavaDtoIndex.clear_cache!
  Noir::TreeSitterKotlinDtoIndex.clear_cache!
end

describe "DTO index scaling" do
  # Every controller sees its whole package; merging the package once per
  # controller made the total time quadratic in the package size.
  it "builds Java indexes in time linear in the package size" do
    small, small_fields = index_package(400, kotlin: false)
    large, large_fields = index_package(800, kotlin: false)
    small_fields.should eq(["a", "b"])
    large_fields.should eq(["a", "b"])
    large.should be < (small * 3 + 300.milliseconds)
  end

  it "builds Kotlin indexes in time linear in the package size" do
    small, small_fields = index_package(600, kotlin: true)
    large, large_fields = index_package(1200, kotlin: true)
    small_fields.should eq(["a", "b"])
    large_fields.should eq(["a", "b"])
    large.should be < (small * 3 + 300.milliseconds)
  end
end
