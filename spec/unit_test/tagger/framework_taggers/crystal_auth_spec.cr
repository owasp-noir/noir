require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "CrystalAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/crystal/kemal_auth", __DIR__)
  app_path = "#{fixture_base}/app.cr"

  # app.cr line reference:
  #  4: get "/profile" do |env|
  #  5:   user = env.session.string("user_id")
  # 10: get "/api/secret" do |env|
  # 11:   basic_auth env
  # 18:   get "/api/health" do |env|  (unprotected, in separate class)

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Kemal session user check" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 4))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("crystal_auth")
  end

  it "detects Kemal basic_auth" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/api/secret", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("basic_auth")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 18))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/api/health", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag a Lucky action that merely reads current_user (false-positive regression)" do
    tmpdir = File.tempname("lucky_fp")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "show.cr")
    File.write(file, [
      "get \"/api/me\" do |env|",
      "  json UserSerializer.new(current_user)",
      "end",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(file, 1))
    details.technology = "crystal_lucky"
    endpoint = Endpoint.new("/api/me", "GET", [] of Param, details)

    CrystalAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.empty?.should be_true

    FileUtils.rm_rf(tmpdir)
  end

  it "keeps a Kemal session check to the route that makes it" do
    tmpdir = File.tempname("kemal_session_scope")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "app.cr")
    File.write(file, <<-'CR')
      require "kemal"

      get "/dashboard" do |env|
        user = env.session.string("user_id")
        "Hi #{user}"
      end

      get "/" do
        "home"
      end

      get "/about" do
        "about"
      end
      CR

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(url : String, line : Int32) do
      details = Details.new(PathInfo.new(file, line))
      details.technology = "crystal_kemal"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    dashboard = at.call("/dashboard", 3)
    root = at.call("/", 8)
    about = at.call("/about", 12)

    CrystalAuthTagger.new(noir_options).perform([dashboard, root, about])
    dashboard.tags.map(&.description).should eq(["Protected by Kemal session user check"])
    root.tags.should be_empty
    about.tags.should be_empty
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "treats Lucky include Auth::AllowGuests as public, not protected" do
    tmpdir = File.tempname("lucky_allow_guests")
    Dir.mkdir_p(tmpdir)
    guest = File.join(tmpdir, "index.cr")
    member = File.join(tmpdir, "show.cr")
    File.write(guest, <<-CR)
      class Home::Index < BrowserAction
        include Auth::AllowGuests

        get "/" do
          html Lucky::WelcomePage
        end
      end
      CR
    File.write(member, <<-CR)
      class Me::Show < BrowserAction
        include Auth::RequireSignIn

        get "/me" do
          html ShowPage
        end
      end
      CR

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(url : String, file : String) do
      details = Details.new(PathInfo.new(file, 4))
      details.technology = "crystal_lucky"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    home = at.call("/", guest)
    me = at.call("/me", member)

    CrystalAuthTagger.new(noir_options).perform([home, me])
    home.tags.should be_empty
    me.tags.map(&.description).should eq(["Protected by Lucky Auth::RequireSignIn"])
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "applies an installed Kemal::Handler to the paths and methods its only list names" do
    tmpdir = File.tempname("kemal_handler")
    Dir.mkdir_p(tmpdir)
    handlers = File.join(tmpdir, "handlers.cr")
    app = File.join(tmpdir, "app.cr")
    File.write(File.join(tmpdir, "shard.yml"), "name: app\n")
    File.write(handlers, <<-CR)
      class TokenAuthHandler < Kemal::Handler
        {% for method in %w[GET DELETE] %}
          only ["/api/me/*"], {{ method }}
        {% end %}
        only ["/admin"]

        def call(env)
          return call_next env unless only_match? env
          return call_next env if env.request.headers["Authorization"]? == "Bearer secret"
          env.response.status_code = 401
        end
      end

      class FrameHandler < Kemal::Handler
        exclude ["/embed/*"]

        def call(env)
          return call_next env if exclude_match? env
          env.response.headers["X-Frame-Options"] = "sameorigin"
          call_next env
        end
      end
      CR
    File.write(app, <<-CR)
      add_handler TokenAuthHandler.new
      add_handler FrameHandler.new
      get "/" do
      end
      CR

    CodeLocator.instance.register_path(handlers)
    CodeLocator.instance.register_path(app)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(url : String, method : String) do
      details = Details.new(PathInfo.new(app, 3))
      details.technology = "crystal_kemal"
      Endpoint.new(url, method, [] of Param, details)
    end
    home = at.call("/", "GET")
    profile = at.call("/api/me/profile", "GET")
    session = at.call("/api/me/sessions/:id", "DELETE")
    admin = at.call("/admin", "GET")
    admin_post = at.call("/admin", "POST")
    embed = at.call("/embed/:id", "GET")

    CrystalAuthTagger.new(noir_options).perform([home, profile, session, admin, admin_post, embed])
    home.tags.should be_empty
    admin_post.tags.should be_empty
    embed.tags.should be_empty
    [profile, session, admin].each do |endpoint|
      endpoint.tags.map(&.description).should eq(["Protected by Kemal TokenAuthHandler handler"])
    end
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "skips a Kemal::Handler whose refusal is not tied to a read of the caller" do
    tmpdir = File.tempname("kemal_handler_unrelated_refusal")
    Dir.mkdir_p(tmpdir)
    handlers = File.join(tmpdir, "handlers.cr")
    app = File.join(tmpdir, "app.cr")
    File.write(File.join(tmpdir, "shard.yml"), "name: app\n")
    File.write(handlers, <<-CR)
      class CorsHandler < Kemal::Handler
        exclude ["/health"]

        def call(env)
          return call_next env if exclude_match? env
          if env.request.headers["Origin"]? != "https://app.example.com"
            env.response.status_code = 403
            return
          end
          env.response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
          call_next env
        end
      end

      class LoggingHandler < Kemal::Handler
        exclude ["/health"]

        def call(env)
          return call_next env if exclude_match? env
          if RateLimiter.exceeded?(env.request.remote_address)
            env.response.status_code = 403
            return
          end
          Log.info { env.session.string?("user_id") }
          call_next env
        end
      end
      CR
    File.write(app, <<-CR)
      add_handler CorsHandler.new
      add_handler LoggingHandler.new
      get "/" do
      end
      CR

    [handlers, app].each { |file| CodeLocator.instance.register_path(file) }
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(app, 3))
    details.technology = "crystal_kemal"
    home = Endpoint.new("/", "GET", [] of Param, details)

    CrystalAuthTagger.new(noir_options).perform([home])
    home.tags.should be_empty
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "ignores add_handler lines in comments and spec files" do
    tmpdir = File.tempname("kemal_handler_scope")
    Dir.mkdir_p(File.join(tmpdir, "spec"))
    handlers = File.join(tmpdir, "handlers.cr")
    app = File.join(tmpdir, "app.cr")
    app_spec = File.join(tmpdir, "spec", "app_spec.cr")
    File.write(File.join(tmpdir, "shard.yml"), "name: app\n")
    File.write(handlers, <<-CR)
      class CommentedOut < Kemal::Handler
        only ["/commented"]

        def call(env)
          return call_next env unless only_match? env
          return call_next env if env.request.headers["Authorization"]?
          env.response.status_code = 401
        end
      end

      class SpecOnly < Kemal::Handler
        only ["/speconly"]

        def call(env)
          return call_next env unless only_match? env
          return call_next env if env.request.headers["Authorization"]?
          env.response.status_code = 401
        end
      end
      CR
    File.write(app, <<-CR)
      # add_handler CommentedOut.new
      get "/commented" do
      end
      CR
    File.write(app_spec, "add_handler SpecOnly.new\n")

    [handlers, app, app_spec].each { |file| CodeLocator.instance.register_path(file) }
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = ["/commented", "/speconly"].map do |url|
      details = Details.new(PathInfo.new(app, 2))
      details.technology = "crystal_kemal"
      Endpoint.new(url, "GET", [] of Param, details)
    end

    CrystalAuthTagger.new(noir_options).perform(endpoints)
    endpoints.each(&.tags.should(be_empty))
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "returns correct target_techs" do
    CrystalAuthTagger.target_techs.should contain("crystal_kemal")
    CrystalAuthTagger.target_techs.should contain("crystal_amber")
    CrystalAuthTagger.target_techs.should contain("crystal_lucky")
  end
end
