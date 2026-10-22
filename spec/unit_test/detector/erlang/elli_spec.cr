require "../../../spec_helper"
require "../../../../src/detector/detectors/erlang/*"

describe "Detect Erlang Elli" do
  options = create_test_options
  instance = Detector::Erlang::Elli.new options

  it "detects elli in rebar.config deps" do
    rebar = <<-ERLANG
      {deps, [
          {elli, "3.3.0"}
      ]}.
      ERLANG

    instance.detect("rebar.config", rebar).should be_true
  end

  it "detects an elli_handler behaviour" do
    callback = <<-ERLANG
      -module(my_callback).
      -behaviour(elli_handler).

      handle(Req, _Args) ->
          handle(Req#req.method, elli_request:path(Req), Req).
      ERLANG

    instance.detect("src/my_callback.erl", callback).should be_true
  end

  it "does not detect plain Erlang modules" do
    plain = <<-ERLANG
      -module(math_utils).
      add(A, B) -> A + B.
      ERLANG

    instance.detect("src/math_utils.erl", plain).should be_false
  end
end
