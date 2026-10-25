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

  it "reads project-wide defaults only from live MIDDLEWARE / settings, not tests or mentions" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_settings_scope")
    files = {
      "proj/settings/base.py" => <<-PY,
        MIDDLEWARE = ["django.contrib.auth.middleware.AuthenticationMiddleware"]
        REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"]}
        PY
      "proj/settings/dev.py" => <<-PY,
        REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.AllowAny"]}
        PY
      "tests/settings.py" => <<-PY,
        MIDDLEWARE = ["django.contrib.auth.middleware.LoginRequiredMiddleware"]
        REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"]}
        PY
      "proj/checks.py" => <<-PY,
        HINT = "add django.contrib.auth.middleware.LoginRequiredMiddleware to MIDDLEWARE"
        PY
      "proj/views.py" => <<-PY,
        def dashboard(request):
            pass

        class ItemViewSet(viewsets.ModelViewSet):
            queryset = None
        PY
    }
    files.each do |rel, body|
      path = File.join(tmpdir, rel)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      views = File.join(tmpdir, "proj/views.py")
      dashboard = Endpoint.new("/dashboard", "GET", [] of Param, Details.new(PathInfo.new(views, 1)))
      items = Endpoint.new("/items", "GET", [] of Param, Details.new(PathInfo.new(views, 4)))

      DjangoAuthTagger.new(noir_options).perform([dashboard, items])

      dashboard.tags.should be_empty
      items.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads @method_decorator(login_required) and wrapped class headers" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_method_decorator")
    Dir.mkdir_p(tmpdir)
    views = File.join(tmpdir, "views.py")
    File.write(views, <<-PY)
      @method_decorator(login_required, name="dispatch")
      class DashboardView(View):
          def get(self, request):
              return HttpResponse("dash")


      class ProfileView(View):
          @method_decorator(login_required)
          def get(self, request):
              return HttpResponse("p")


      class WrappedView(
          LoginRequiredMixin,
          View,
      ):
          def get(self, request):
              return HttpResponse("w")


      @method_decorator(login_required, name="post")
      class FormView(View):
          def get(self, request):
              return HttpResponse("f")


      class OpenView(View):
          def get(self, request):
              return HttpResponse("o")
      PY

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      dash, profile, wrapped, form, open = [3, 9, 17, 23, 28].map do |line|
        Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(views, line)))
      end

      DjangoAuthTagger.new(noir_options).perform([dash, profile, wrapped, form, open])

      dash.tags.map(&.description).should eq(["Protected by Django login_required decorator"])
      profile.tags.map(&.description).should eq(["Protected by Django login_required decorator"])
      wrapped.tags.map(&.description).should eq(["Protected by Django LoginRequiredMixin"])
      form.tags.should be_empty
      open.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "judges DRF permission classes by their definition, through same-file bases" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_drf_custom_perms")
    Dir.mkdir_p(tmpdir)
    perms = File.join(tmpdir, "permissions.py")
    views = File.join(tmpdir, "views.py")
    File.write(perms, <<-PY)
      class StaffOnly(BasePermission):
          def has_permission(self, request, view):
              return request.user.is_staff

      class Anyone(BasePermission):
          def has_permission(self, request, view):
              return True

      class OwnerObjects(DjangoObjectPermissions):
          pass

      class ReadOrStaff(BasePermission):
          def has_permission(self, request, view):
              if request.method in SAFE_METHODS:
                  return True
              return request.user.is_staff
      PY
    File.write(views, <<-PY)
      class StaffView(APIView):
          permission_classes = [StaffOnly]
          def get(self, request):
              pass

      class OpenView(APIView):
          permission_classes = [Anyone]
          def get(self, request):
              pass

      class OwnedMixin(GenericAPIView):
          permission_classes = (OwnerObjects,)

      class OwnedView(
          OwnedMixin,
      ):
          class _Filter(BaseFilter):
              pass

          def get(self, request):
              pass

      class EitherView(APIView):
          permission_classes = [IsAuthenticated | Anyone]
          def get(self, request):
              pass

      class ReadView(APIView):
          permission_classes = [ReadOrStaff]
          def get(self, request):
              pass
          def post(self, request):
              pass
      PY
    CodeLocator.instance.register_path(perms)
    CodeLocator.instance.register_path(views)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      staff = at.call("GET", 3)
      open = at.call("GET", 8)
      owned = at.call("GET", 20)
      either = at.call("GET", 25)
      read = at.call("GET", 30)
      write = at.call("POST", 32)

      DjangoAuthTagger.new(noir_options).perform([staff, open, owned, either, read, write])

      staff.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
      open.tags.should be_empty
      owned.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
      either.tags.should be_empty
      read.tags.should be_empty
      write.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "judges project decorators, view-body checks and dispatchers by definition" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_function_view_guards")
    Dir.mkdir_p(tmpdir)
    decorators = File.join(tmpdir, "decorators.py")
    views = File.join(tmpdir, "views.py")
    File.write(decorators, <<-PY)
      def authorize(f):
          def wrapper(request, *args, **kwds):
              if "X-Api-Key" not in request.headers:
                  return JsonResponse({"error": "missing api key"}, status=401)
              return f(request, *args, **kwds)
          return wrapper

      def cors(f):
          def wrapper(request, *args, **kwds):
              response = f(request, *args, **kwds)
              if request.method == "OPTIONS":
                  return HttpResponse(status=204)
              return response
          return wrapper
      PY
    File.write(views, <<-PY)
      from .decorators import authorize, cors

      @authorize
      def create(request):
          pass

      @cors
      def listing(request):
          pass

      def dispatch(request):
          if request.method == "POST":
              return create(request)
          return listing(request)

      def events(request, code):
          if not request.user.is_authenticated:
              return HttpResponseForbidden()
          return render(request, "events.html")

      def late(request):
          if request.method == "GET":
              return render(request, "x.html")
          if not request.user.is_authenticated:
              return HttpResponseForbidden()
      PY
    CodeLocator.instance.register_path(decorators)
    CodeLocator.instance.register_path(views)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{method}#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      direct = at.call("POST", 4)
      plain = at.call("GET", 8)
      dispatch_post = at.call("POST", 11)
      dispatch_get = at.call("GET", 11)
      events = at.call("GET", 16)
      late_post = at.call("POST", 21)
      late_get = at.call("GET", 21)

      DjangoAuthTagger.new(noir_options).perform([direct, plain, dispatch_post, dispatch_get, events, late_post, late_get])

      direct.tags.map(&.description).should eq(["Protected by authorize"])
      plain.tags.should be_empty
      dispatch_post.tags.map(&.description).should eq(["Protected by authorize (via create)"])
      dispatch_get.tags.should be_empty
      events.tags.map(&.description).should eq(["Protected by Django request.user.is_authenticated check"])
      # GET is answered by the branch above the check; POST still meets it.
      late_post.tags.map(&.description).should eq(["Protected by Django request.user.is_authenticated check"])
      late_get.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
end
