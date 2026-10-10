require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "DjangoAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/python/django_auth", __DIR__)
  views_path = "#{fixture_base}/blog/views.py"

  # views.py line reference:
  # 10: def public_page(request):
  # 14: @login_required
  # 15: def post_list(request):
  # 19: @permission_required('blog.add_post')
  # 20: def post_create(request):
  # 24: class PostDetailView(LoginRequiredMixin, DetailView):
  # 25:     model = None
  # 29: class PostAPIView(APIView):
  # 30:     permission_classes = [IsAuthenticated]
  # 32:     def get(self, request):

  it "detects @login_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(views_path, 15))
    details.technology = "python_django"
    endpoint = Endpoint.new("/posts/", "GET", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("django_auth")
    endpoint.tags[0].description.should contain("login_required")
  end

  it "detects @permission_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(views_path, 20))
    details.technology = "python_django"
    endpoint = Endpoint.new("/posts/create/", "POST", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("permission_required")
  end

  it "detects LoginRequiredMixin in class" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(views_path, 25))
    details.technology = "python_django"
    endpoint = Endpoint.new("/posts/1/", "GET", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("LoginRequiredMixin")
  end

  it "detects DRF permission_classes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(views_path, 32))
    details.technology = "python_django"
    endpoint = Endpoint.new("/api/posts/", "GET", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("DRF permission_classes")
  end

  it "does not tag unprotected views" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(views_path, 10))
    details.technology = "python_django"
    endpoint = Endpoint.new("/public/", "GET", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "python_django"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = DjangoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "applies LoginRequiredMiddleware and DRF defaults, honouring opt-outs" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_global_auth")
    Dir.mkdir_p(tmpdir)
    settings = File.join(tmpdir, "settings.py")
    views = File.join(tmpdir, "views.py")
    File.write(settings, <<-PY)
      MIDDLEWARE = [
          "django.contrib.auth.middleware.AuthenticationMiddleware",
          "django.contrib.auth.middleware.LoginRequiredMiddleware",
      ]
      REST_FRAMEWORK = {
          "DEFAULT_PERMISSION_CLASSES": [
              "rest_framework.permissions.IsAuthenticated",
          ],
      }
      PY
    File.write(views, <<-PY)
      def dashboard(request):
          pass

      @login_not_required
      def about(request):
          pass

      class SignInView(LoginView):
          pass

      @api_view(["GET"])
      @permission_classes([AllowAny])
      def ping(request):
          pass

      class ItemViewSet(viewsets.ModelViewSet):
          queryset = None

      class NoteViewSet(viewsets.ModelViewSet):
          permission_classes = [IsAuthenticatedOrReadOnly]
      PY
    CodeLocator.instance.register_path(settings)
    CodeLocator.instance.register_path(views)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      dashboard = at.call("GET", 1)
      about = at.call("GET", 5)
      sign_in = at.call("GET", 8)
      ping = at.call("GET", 13)
      items = at.call("GET", 16)
      notes_read = at.call("GET", 19)
      notes_write = at.call("POST", 19)

      DjangoAuthTagger.new(noir_options).perform([dashboard, about, sign_in, ping, items, notes_read, notes_write])

      dashboard.tags.map(&.description).should eq(["Protected by Django LoginRequiredMiddleware"])
      about.tags.should be_empty
      sign_in.tags.should be_empty
      ping.tags.should be_empty
      items.tags.map(&.description).should eq(["Protected by DRF DEFAULT_PERMISSION_CLASSES"])
      notes_read.tags.should be_empty
      notes_write.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
end
