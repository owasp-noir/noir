require "../../spec_helper"
require "../../../src/analyzer/analyzers/elixir/elixir_plug"

private def plug_routes(source : String) : Hash(String, Array(String))
  analyzer = Analyzer::Elixir::Plug.new(create_test_options)
  analyzer.analyze_content(source, "lib/router.ex").to_h do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |p| "#{p.name}:#{p.param_type}" }}
  end
end

describe Analyzer::Elixir::Plug do
  it "keeps an inline `do:` route to its own line and skips commented-out routes" do
    source = <<-ELIXIR
      defmodule MyRouter do
        use Plug.Router
        get "/inline", do: send_resp(conn, 200, conn.params["q"])
        post "/block" do
          s = conn.params["secret"]
          h = get_req_header(conn, "x-secret")
          send_resp(conn, 200, "ok")
        end
        get "/download", to: DownloadPlug
        put "/after" do
          send_resp(conn, 200, conn.params["after"])
        end
        # get "/commented", do: send_resp(conn, 200, "x")
        delete "/trailing" do # get "/in-trailing-comment"
          # conn.params["commented_param"]
          send_resp(conn, 204, "")
        end
      end
      ELIXIR

    routes = plug_routes(source)
    routes.keys.should eq(["GET /inline", "POST /block", "GET /download", "PUT /after", "DELETE /trailing"])
    routes["GET /inline"].should eq(["q:query"])
    routes["POST /block"].should eq(["secret:form", "x-secret:header"])
    routes["GET /download"].should be_empty
    routes["PUT /after"].should eq(["after:form"])
    routes["DELETE /trailing"].should be_empty
  end
end
