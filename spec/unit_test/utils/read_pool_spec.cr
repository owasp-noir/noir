require "file_utils"
require "../../spec_helper"
require "../../../src/utils/read_pool"
require "../../../src/detector/detector"
require "../../../src/models/code_locator"
require "../../../src/models/logger"

describe Noir::ReadPool do
  it "returns one outcome per submitted path: content, binary flag, or error" do
    dir = File.tempname("noir-read-pool")
    Dir.mkdir_p(dir)
    begin
      text = File.join(dir, "a.py")
      blob = File.join(dir, "b.py")
      File.write(text, "print('hi')\n")
      File.write(blob, Bytes[0x61, 0x00, 0x62])

      pool = Noir::ReadPool.new
      replies = [text, blob, File.join(dir, "missing.py")].map { |path| pool.submit(path) }
      outcomes = replies.map(&.receive)
      pool.close

      outcomes[0].content.should eq("print('hi')\n")
      outcomes[0].binary.should be_false
      outcomes[1].binary.should be_true
      outcomes[2].content.should be_nil
      outcomes[2].error.should be_a(File::NotFoundError)
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe "detect_techs with parallel reads" do
  # Reads complete out of order on the pool; everything after the read must
  # still see files in walk order. For a flat directory that is the order
  # `Dir.each_child` lists it in, and it is the order analyzers iterate.
  it "registers files in walk order even when reads finish out of order" do
    dir = File.tempname("noir-read-order")
    Dir.mkdir_p(dir)
    begin
      200.times do |i|
        # Sizes vary a lot so later files often finish reading first.
        File.write(File.join(dir, "mod_#{i}.py"), "import os\n" + ("x = #{i}\n" * ((i * 37) % 97 * 50)))
      end
      File.write(File.join(dir, "notes.bin"), Bytes[0x00, 0x01])
      expected = [] of String
      Dir.each_child(dir) { |entry| expected << File.join(dir, entry) if entry.ends_with?(".py") }

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detect_techs([dir], options, [] of PassiveScan, logger)
      locator.all_files.select(&.ends_with?(".py")).should eq(expected)
      expected.each { |path| locator.content_for(path).should eq(File.read(path)) }
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
