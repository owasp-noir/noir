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

    it "keeps a Content-Type header param instead of adding a second one" do
      cmd = CurlCommand.build("POST", "/c", "a=1", "form", ["content-type: application/x-www-form-urlencoded; charset=utf-8"], [] of String)
      cmd.should eq("curl -i -g -X 'POST' '/c' --data-raw 'a=1' -H 'content-type: application/x-www-form-urlencoded; charset=utf-8'")
    end

    it "lets the body's Content-Type replace an empty Content-Type header param" do
      cmd = CurlCommand.build("POST", "/c", "{}", "json", ["Content-Type: ", "X-A: 1"], [] of String)
      cmd.should eq("curl -i -g -X 'POST' '/c' --data-raw '{}' -H 'Content-Type: application/json' -H 'X-A: 1'")
    end

    it "uses -I for HEAD, since -X HEAD waits for a body that never comes" do
      cmd = CurlCommand.build("HEAD", "/test", "", "", [] of String, [] of String)
      cmd.should eq("curl -I -g '/test'")
    end

    it "sends an empty header with curl's `Name;` syntax" do
      cmd = CurlCommand.build("GET", "/test", "", "", ["X-Token: ", "Accept: "], [] of String)
      cmd.should eq("curl -i -g -X 'GET' '/test' -H 'X-Token;' -H 'Accept;'")
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
