require "../../../spec_helper"
require "../../../../src/detector/detectors/c/*"

describe "Detect C libmicrohttpd" do
  options = create_test_options
  instance = Detector::C::Libmicrohttpd.new options

  it "includes microhttpd.h" do
    instance.detect("server.c", "#include <microhttpd.h>").should be_true
  end

  it "starts a daemon" do
    instance.detect("server.c", "d = MHD_start_daemon (flags, 8080, NULL, NULL, &ahc, NULL, MHD_OPTION_END);").should be_true
  end

  it "plain C file" do
    instance.detect("server.c", "#include <stdlib.h>").should be_false
  end
end
