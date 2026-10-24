require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# `list[A | B] | None` peels to `list[A | B]`, whose `|` sits inside the
# brackets; the model-name peeler used to spin on it forever (mealie hung).
describe "FastAPI union annotations" do
  it "finishes on a union nested inside a generic" do
    root = File.tempname("noir-fastapi-union")
    Dir.mkdir_p(root)
    File.write(File.join(root, "requirements.txt"), "fastapi\n")
    File.write(File.join(root, "app.py"), <<-PY)
      from fastapi import APIRouter, Query
      router = APIRouter()

      @router.get("/x")
      def get_all(categories: list[UUID4 | str] | None = Query(None)):
          return 1
      PY
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints.flat_map(&.params.map(&.name)).should contain("categories")
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(root) if root && Dir.exists?(root)
  end
end
