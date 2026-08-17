require "spec"
require "../../../src/llm/prompt"

# `bundle_files` decides what actually reaches the provider. A bundle that
# overshoots the model's context window is rejected with a 400, the client
# maps that to "", and every endpoint in the files it carried disappears
# without a trace — so the size guarantee below is a detection guarantee.
#
# 4000 tokens is the global default `get_max_tokens` falls back to for any
# provider it does not recognise (a custom gateway URL, for instance), and
# the 0.8 safety margin puts the per-bundle ceiling at 3200.
private SAFE_LIMIT = 3200

# The source text a bundle section wraps, without the header and fences.
private def section_body(bundle : LLM::Bundle) : String
  content = bundle.content
  start = content.index!("```\n") + 4
  finish = content.rindex!("\n```\n")
  content[start...finish]
end

describe LLM do
  describe ".bundle_files" do
    it "packs small files together and reports the files each bundle carries" do
      files = [
        {"a.rb", "get '/a'"},
        {"b.rb", "get '/b'"},
      ]

      bundles = LLM.bundle_files(files, 4000)
      bundles.size.should eq(1)
      bundles[0].paths.should eq(["a.rb", "b.rb"])
      bundles[0].content.should contain("a.rb")
      bundles[0].content.should contain("b.rb")
    end

    it "splits a single file that cannot fit instead of emitting an over-budget bundle" do
      # One file past the ceiling used to be appended unconditionally,
      # because the flush above it is guarded on the accumulator being
      # non-empty. The provider answered 400 and the file's endpoints were
      # gone.
      big = Array.new(4000) { |i| "get '/route/#{i}' do 'ok' end" }.join("\n")
      big.size.should be > 12_000

      bundles = LLM.bundle_files([{"big.rb", big}], 4000)
      bundles.size.should be > 1
      bundles.each do |bundle|
        bundle.paths.should eq(["big.rb"])
        bundle.tokens.should be <= SAFE_LIMIT
      end
    end

    it "keeps every byte of a split file, in order" do
      big = Array.new(4000) { |i| "get '/route/#{i}' do 'ok' end" }.join("\n")
      bundles = LLM.bundle_files([{"big.rb", big}], 4000)

      bundles.map { |bundle| section_body(bundle) }.join.should eq(big)
    end

    it "labels the parts of a split file so the model knows they belong together" do
      big = Array.new(4000) { |i| "get '/route/#{i}' do 'ok' end" }.join("\n")
      bundles = LLM.bundle_files([{"big.rb", big}], 4000)

      total = bundles.size
      bundles.each_with_index do |bundle, index|
        bundle.content.should contain(%(- File: "big.rb" (part #{index + 1}/#{total})))
      end
    end

    it "never cuts in the middle of a multi-byte character" do
      # A byte-offset slice here would hand the provider invalid UTF-8.
      big = Array.new(3000) { |i| "get '/경로/#{i}' do '한글 응답' end" }.join("\n")
      bundles = LLM.bundle_files([{"한글.rb", big}], 4000)

      bundles.size.should be > 1
      bundles.each do |bundle|
        bundle.content.valid_encoding?.should be_true
        bundle.tokens.should be <= SAFE_LIMIT
      end
      bundles.map { |bundle| section_body(bundle) }.join.should eq(big)
    end

    it "splits a file that is one enormous line with no newline to break on" do
      big = "x" * 100_000
      bundles = LLM.bundle_files([{"minified.js", big}], 4000)

      bundles.size.should be > 1
      bundles.each(&.tokens.should(be <= SAFE_LIMIT))
      bundles.map { |bundle| section_body(bundle) }.join.should eq(big)
    end

    it "flushes the accumulated files before the oversized one, losing none of them" do
      big = "get '/big' do 'ok' end\n" * 2000
      files = [
        {"small.rb", "get '/small'"},
        {"big.rb", big},
        {"after.rb", "get '/after'"},
      ]

      bundles = LLM.bundle_files(files, 4000)
      bundles.flat_map(&.paths).uniq!.sort!.should eq(["after.rb", "big.rb", "small.rb"])
      bundles.each(&.tokens.should(be <= SAFE_LIMIT))
    end

    it "still produces a bundle for an empty file" do
      bundles = LLM.bundle_files([{"empty.rb", ""}], 4000)
      bundles.size.should eq(1)
      bundles[0].paths.should eq(["empty.rb"])
    end
  end
end
