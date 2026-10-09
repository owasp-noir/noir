require "../../spec_helper"
require "../../../src/analyzer/engines/ruby_engine"

private def mask(source : String) : String
  Analyzer::Ruby::RubyEngine.mask_non_code(source)
end

describe "Analyzer::Ruby::RubyEngine.mask_non_code" do
  it "blanks =begin/=end blocks, heredoc bodies and everything after __END__, keeping line count" do
    source = <<-RUBY
      get '/real' do
      =begin
      get '/dead' do
      =end
      DOC = <<~TXT
        get '/in-heredoc' do
        TXT
      SQL = <<-'Q'
      get '/in-quoted'
      Q
      put '/after-heredocs' do
      __END__
      get '/afterend' do
      RUBY

    masked = mask(source)
    masked.count('\n').should eq(source.count('\n'))
    masked.should contain("get '/real' do")
    masked.should contain("DOC = <<~TXT")
    masked.should contain("put '/after-heredocs' do")
    masked.should_not contain("/dead")
    masked.should_not contain("/in-heredoc")
    masked.should_not contain("/in-quoted")
    masked.should_not contain("/afterend")
  end

  it "reads several heredocs opened on one line in order" do
    source = "call(<<~A, <<~B)\n  get '/a'\n  A\n  get '/b'\n  B\nget '/live'\n"
    mask(source).should eq("call(<<~A, <<~B)\n\n\n\n\nget '/live'\n")
  end

  it "leaves shifts, appends, quoted and commented `<<` and unterminated openers alone" do
    source = <<-RUBY
      x = 1<<FLAGS
      class << self
      s = "<<~NOPE"
      y = 2 # <<~NOPE
      z = <<~NEVER_CLOSED
      get '/kept' do
      NOPE
      RUBY
    mask(source).should eq(source)
  end

  it "requires a bare <<ID terminator at column 0" do
    source = "a = <<EOS\n  EOS\nget '/in-body'\nEOS\nget '/live'\n"
    mask(source).should eq("a = <<EOS\n\n\n\nget '/live'\n")
  end

  it "keeps <<~RUBY bodies, which are eval'd code" do
    source = "class_eval <<~RUBY\n  get '/generated' do\n  end\nRUBY\n"
    mask(source).should eq(source)
  end

  it "is not quadratic on many unterminated openers" do
    source = String.build do |io|
      20_000.times { |i| io << "a#{i} = <<~X#{i}\nget '/r#{i}'\n" }
    end
    elapsed = Time.measure { mask(source).should eq(source) }
    elapsed.should be < 2.seconds
  end
end
