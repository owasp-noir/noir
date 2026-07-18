require "../../../spec_helper"
require "../../../../src/detector/detectors/erlang/*"

describe "Detect Erlang Cowboy" do
  options = create_test_options
  instance = Detector::Erlang::Cowboy.new options

  it "detects cowboy in rebar.config deps" do
    rebar = <<-ERLANG
      {erl_opts, [debug_info]}.

      {deps, [
          {cowboy, "2.10.0"},
          {jsx, "3.1.0"}
      ]}.
      ERLANG

    instance.detect("rebar.config", rebar).should be_true
  end

  it "detects a dispatch table in an .erl file" do
    app = <<-'ERLANG'
      -module(my_app).

      start(_Type, _Args) ->
          Dispatch = cowboy_router:compile([
              {'_', [{"/", hello_handler, []}]}
          ]),
          cowboy:start_clear(http, [{port, 8080}], #{env => #{dispatch => Dispatch}}).
      ERLANG

    instance.detect("src/my_app.erl", app).should be_true
  end

  it "detects a cowboy_rest behaviour" do
    handler = <<-ERLANG
      -module(user_handler).
      -behaviour(cowboy_rest).

      init(Req, State) -> {cowboy_rest, Req, State}.
      ERLANG

    instance.detect("src/user_handler.erl", handler).should be_true
  end

  # Elixir projects pull Cowboy in through plug_cowboy, but their routes
  # live in Phoenix/Plug routers the Elixir analyzers already own.
  it "does not detect Cowboy from an Elixir mix.exs" do
    mix = <<-ELIXIR
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          [
            {:plug, "~> 1.14"},
            {:plug_cowboy, "~> 2.5"}
          ]
        end
      end
      ELIXIR

    instance.detect("mix.exs", mix).should be_false
    instance.applicable?("mix.exs").should be_false
  end

  it "does not detect plain Erlang modules" do
    plain = <<-ERLANG
      -module(math_utils).
      -export([add/2]).

      add(A, B) -> A + B.
      ERLANG

    instance.detect("src/math_utils.erl", plain).should be_false
  end
end
