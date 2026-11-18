require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

describe "swift_cli ArgumentParser names" do
  it "reads customLong inside a name array, kebab-cases default names and skips wrappers in strings" do
    temp_dir = File.tempname("swift_cli_names")
    Dir.mkdir_p(temp_dir)
    File.write(File.join(temp_dir, "Tool.swift"), <<-SWIFT)
      import ArgumentParser

      struct Tool: ParsableCommand {
          static let configuration = CommandConfiguration(
              commandName: "tool",
              subcommands: [ExportItems.self]
          )
      }

      struct ExportItems: ParsableCommand {
          @Option(name: [.customShort("n"), .customLong("itemName")],
                  help: "Item name")
          var itemName: String?
          @Flag(name: [.short, .customLong("dryRun")])
          var dryRun = false
          @Flag var includeOrderID = false

          func run() throws {
              print("Each @Flag var *: Bool is an item column.")
          }

          private var cacheKey: String { "" }
      }
      SWIFT

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints.select(&.method.==("CLI")).to_h { |e| {e.url, e.params.map(&.name)} }.should eq({
      "cli://tool"              => [] of String,
      "cli://tool/export-items" => ["itemName", "dryRun", "include-order-id"],
    })
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
