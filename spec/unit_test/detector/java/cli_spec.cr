require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java CLI" do
  options = create_test_options
  instance = Detector::Java::Cli.new options

  {
    "import com.beust.jcommander.Parameter;"                         => true,
    "import com.beust.jcommander.JCommander;"                        => true,
    "import com.beust.jcommander.Parameters;"                        => true,
    "import com.beust.jcommander.*;"                                 => true,
    "import com.beust.jcommander.internal.Maps;"                     => false,
    "import com.beust.jcommander.ParameterException;"                => false,
    "import picocli.CommandLine;"                                    => true,
    "import com.beust.jcommander.internal.Maps;\nnew JCommander(x);" => true,
  }.each do |source, expected|
    it "#{source.inspect} -> #{expected}" do
      instance.detect("Tool.java", source).should eq expected
    end
  end
end
