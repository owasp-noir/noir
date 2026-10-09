require "../../../src/utils/curl_command"

describe CurlCommand do
  describe ".shell_quote" do
    it "wraps strings in single quotes" do
      CurlCommand.shell_quote("/test").should eq("'/test'")
    end

    it "escapes embedded single quotes" do
      CurlCommand.shell_quote("it's").should eq("'it'\\''s'")
    end
  end

  describe ".build" do
    it "builds a bare request" do
      cmd = CurlCommand.build("GET", "/test?id=1", "", "", [] of String, [] of String)
      cmd.should eq("curl -i -g -X 'GET' '/test?id=1'")
    end

    it "passes -g so {id} and [..] in the URL are not glob-expanded by curl" do
      cmd = CurlCommand.build("GET", "/users/{id}?filter[name]=", "", "", [] of String, [] of String)
      cmd.should eq("curl -i -g -X 'GET' '/users/{id}?filter[name]='")
    end

    it "adds a JSON body with content type" do
      cmd = CurlCommand.build("POST", "/api/users", "{\"name\":\"noir\"}", "json", [] of String, [] of String)
      cmd.should contain("--data-raw '{\"name\":\"noir\"}'")
      cmd.should contain("-H 'Content-Type: application/json'")
    end

    it "adds a form body with content type" do
      cmd = CurlCommand.build("PUT", "/api/products", "name=Updated Product&price=99.99", "form", [] of String, [] of String)
      cmd.should contain("--data-raw 'name=Updated Product&price=99.99'")
      cmd.should contain("-H 'Content-Type: application/x-www-form-urlencoded'")
    end

    it "adds headers and cookies" do
      cmd = CurlCommand.build("GET", "/test", "", "", ["x-api-key: key123"], ["session=abc123"])
      cmd.should contain("-H 'x-api-key: key123'")
      cmd.should contain("--cookie 'session=abc123'")
    end
  end

  describe ".build_multipart" do
    it "sends text fields with --form-string and file parts with -F" do
      cmd = CurlCommand.build_multipart("POST", "/upload", [{"name", "@/etc/passwd"}, {"bio", "<x"}],
        [{"avatar", ""}], [] of String, [] of String)
      cmd.should eq("curl -i -g -X 'POST' '/upload' --form-string 'name=@/etc/passwd' --form-string 'bio=<x' -F 'avatar=@avatar'")
    end
  end
end
