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

  it "reads an early anonymous refusal through a request.user alias and self.request, unconditional and before any write" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_body_alias_guards")
    Dir.mkdir_p(tmpdir)
    views = File.join(tmpdir, "views.py")
    File.write(views, <<-PY)
      def flags(request):
          user = request.user
          if not user.is_authenticated:
              return HttpResponseForbidden()
          return HttpResponse("ok")

      def inverted(request):
          if not request.user.is_anonymous:
              return HttpResponseForbidden()
          return HttpResponse("ok")

      class Things(APIView):
          def get(self, request):
              if self.request.user.is_anonymous:
                  return redirect(settings.LOGIN_URL)
              return Response({})

      def elsewhere(request):
          user = request.user
          if not user.is_authenticated:
              return redirect("home")
          return HttpResponse("ok")

      def reassigned(request):
          user = request.user
          user = User.objects.get(pk=1)
          if not user.is_authenticated:
              return HttpResponseForbidden()
          return HttpResponse("ok")

      def subbranch(request):
          if not request.user.is_authenticated:
              if request.GET.get("strict"):
                  return HttpResponseForbidden()
              messages.info(request, "guest")
          return render(request, "x.html")

      def written_first(request):
          Item.objects.filter(pk=1).delete()
          if not request.user.is_authenticated:
              return HttpResponseForbidden()
          return HttpResponse("ok")

      def negated_paren(request):
          if not(request.user.is_anonymous):
              return HttpResponseForbidden()
          return HttpResponse("ok")

      def signed_in_first(request):
          if not request.user.is_anonymous:
              if not request.user.has_perm("app.edit"):
                  raise PermissionDenied
              return HttpResponse("secret")
          return redirect_to_login(request.get_full_path())

      def signed_in_or(request):
          if request.user.is_authenticated or settings.PUBLIC:
              return HttpResponse("page")
          return HttpResponseForbidden()
      PY
    CodeLocator.instance.register_path(views)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(views, line))) }
      flags = at.call(1)
      inverted = at.call(7)
      things = at.call(13)
      elsewhere = at.call(18)
      reassigned = at.call(24)
      subbranch = at.call(31)
      written_first = at.call(38)
      negated_paren = at.call(44)
      signed_in_first = at.call(49)
      signed_in_or = at.call(56)

      DjangoAuthTagger.new(noir_options).perform([flags, inverted, things, elsewhere, reassigned, subbranch, written_first, negated_paren, signed_in_first, signed_in_or])

      flags.tags.map(&.description).should eq(["Protected by Django request.user.is_authenticated check"])
      # `not ... is_anonymous` refuses the signed-in caller, not the anonymous one.
      inverted.tags.should be_empty
      things.tags.map(&.description).should eq(["Protected by Django request.user.is_authenticated check"])
      # A redirect anywhere but the login page is not a refusal.
      elsewhere.tags.should be_empty
      # The alias was rebound before the check: another user is tested.
      reassigned.tags.should be_empty
      # Only some anonymous callers are refused; the rest get the page.
      subbranch.tags.should be_empty
      # The anonymous caller's delete has already run.
      written_first.tags.should be_empty
      negated_paren.tags.should be_empty
      # Signed-in callers leave inside the block; everyone else is refused.
      signed_in_first.tags.map(&.description).should eq(["Protected by Django request.user.is_authenticated check"])
      # `or` lets an anonymous caller into the block.
      signed_in_or.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "judges class-based views by the dispatch their project bases define" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_cbv_dispatch")
    Dir.mkdir_p(File.join(tmpdir, "pkg"))
    init = File.join(tmpdir, "pkg", "__init__.py")
    mixins = File.join(tmpdir, "pkg", "mixins.py")
    views = File.join(tmpdir, "views.py")
    File.write(init, "from .mixins import *\n")
    File.write(mixins, <<-PY)
      class ConditionalLogin(AccessMixin):
          def dispatch(self, request, *args, **kwargs):
              if settings.LOGIN_REQUIRED and not request.user.is_authenticated:
                  return self.handle_no_permission()
              return super().dispatch(request, *args, **kwargs)

      class PermRequired(ConditionalLogin):
          def has_permission(self):
              return self.request.user.has_perms(("x",))

          def dispatch(self, request, *args, **kwargs):
              if not self.has_permission():
                  return self.handle_no_permission()
              return super().dispatch(request, *args, **kwargs)

      class TokenOnly(View):
          def dispatch(self, request, *args, **kwargs):
              if not request.user.is_authenticated:
                  try:
                      authenticate(request)
                  except Failed:
                      return HttpResponseForbidden("bad token")
              return super().dispatch(request, *args, **kwargs)

      class Replaces(ConditionalLogin):
          def dispatch(self, request, *args, **kwargs):
              return View.dispatch(self, request, *args, **kwargs)
      PY
    File.write(views, <<-PY)
      from pkg import ConditionalLogin, PermRequired, TokenOnly, Replaces

      class HomeView(ConditionalLogin, View):
          def get(self, request):
              pass

      class ItemView(PermRequired, View):
          def get(self, request):
              pass

      class TokenView(TokenOnly, View):
          def get(self, request):
              pass

      class ReplacedView(Replaces):
          def get(self, request):
              pass
      PY
    [init, mixins, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(views, line))) }
      home, item, token, replaced = at.call(4), at.call(8), at.call(12), at.call(16)

      DjangoAuthTagger.new(noir_options).perform([home, item, token, replaced])

      # The setting the refusal tests is named, so an absent guard is never
      # read as "anonymous OK" while a setting decides it.
      home.tags.map(&.description).should eq(["Protected by ConditionalLogin.dispatch (settings.LOGIN_REQUIRED decides; a setting can make it public)"])
      item.tags.map(&.description).should eq(["Protected by PermRequired.dispatch"])
      # A refusal nested in a token check's `except` turns away a bad token,
      # not an anonymous caller; a dispatch that skips `super()` drops the
      # base's check.
      token.tags.should be_empty
      replaced.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "follows a DRF permission's super() delegation and the authenticated_users_only it sets" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_drf_delegating_perms")
    Dir.mkdir_p(tmpdir)
    settings = File.join(tmpdir, "settings.py")
    perms = File.join(tmpdir, "perms.py")
    views = File.join(tmpdir, "views.py")
    File.write(settings, <<-PY)
      REST_FRAMEWORK = {
          "DEFAULT_PERMISSION_CLASSES": ("app.perms.TokenPerms",),
      }
      PY
    File.write(perms, <<-PY)
      class TokenPerms(DjangoObjectPermissions):
          def __init__(self):
              self.authenticated_users_only = settings.LOGIN_REQUIRED
              super().__init__()

          def has_permission(self, request, view):
              if isinstance(request.auth, Token) and not request.auth.write_enabled:
                  return False
              return super().has_permission(request, view)

      class OpenModelPerms(DjangoModelPermissions):
          authenticated_users_only = False
      PY
    File.write(views, <<-PY)
      class ItemViewSet(viewsets.ModelViewSet):
          queryset = None

      class OpenViewSet(viewsets.ModelViewSet):
          permission_classes = [OpenModelPerms]
      PY
    [settings, perms, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      items = Endpoint.new("/items/", "GET", [] of Param, Details.new(PathInfo.new(views, 1)))
      open = Endpoint.new("/open/", "GET", [] of Param, Details.new(PathInfo.new(views, 4)))

      DjangoAuthTagger.new(noir_options).perform([items, open])

      items.tags.map(&.description).should eq(["Protected by DRF DEFAULT_PERMISSION_CLASSES (settings.LOGIN_REQUIRED decides; a setting can make it public)"])
      open.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "tags a dispatch only where it refuses an anonymous caller of that verb, in MRO order" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_cbv_dispatch_scope")
    Dir.mkdir_p(tmpdir)
    views = File.join(tmpdir, "views.py")
    File.write(views, <<-PY)
      class SignupView(View):
          def dispatch(self, request, *args, **kwargs):
              if request.user.is_authenticated:
                  raise PermissionDenied
              return super().dispatch(request, *args, **kwargs)

          def get(self, request):
              return None

      class PostOnlyView(View):
          def dispatch(self, request, *args, **kwargs):
              if request.method == "POST" and not request.user.is_authenticated:
                  return self.handle_no_permission()
              return super().dispatch(request, *args, **kwargs)

          def get(self, request):
              return None

          def post(self, request):
              return None

      class ProjectGuard:
          def dispatch(self, request, *args, **kwargs):
              if not request.user.is_authenticated:
                  return redirect_to_login(request.get_full_path())
              return super().dispatch(request, *args, **kwargs)

      class MixinAfterView(View, ProjectGuard):
          def get(self, request):
              return None

      class SoftLogin(LoginRequiredMixin):
          def handle_no_permission(self):
              return None

      class SoftView(SoftLogin, View):
          def get(self, request):
              return None
      PY
    CodeLocator.instance.register_path(views)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      signup = at.call("GET", 7)
      post_only_read = at.call("GET", 16)
      post_only_write = at.call("POST", 19)
      mixin_after = at.call("GET", 29)
      soft = at.call("GET", 37)

      DjangoAuthTagger.new(noir_options).perform([signup, post_only_read, post_only_write, mixin_after, soft])

      # Refusing a logged-in caller is no guard.
      signup.tags.should be_empty
      # A verb-scoped refusal guards that verb only.
      post_only_read.tags.should be_empty
      post_only_write.tags.map(&.description).should eq(["Protected by PostOnlyView.dispatch"])
      # `View.dispatch` comes first in the MRO and never calls `super()`.
      mixin_after.tags.should be_empty
      # The mixin refuses through a `handle_no_permission` that lets the
      # caller through.
      soft.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads a DRF permission's own early returns before its super() delegation" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_drf_early_returns")
    Dir.mkdir_p(tmpdir)
    perms = File.join(tmpdir, "perms.py")
    views = File.join(tmpdir, "views.py")
    File.write(perms, <<-PY)
      class AuthPermission(BasePermission):
          def has_permission(self, request, view):
              return request.user.is_authenticated

      class SafeOpen(AuthPermission):
          def has_permission(self, request, view):
              if request.method in SAFE_METHODS:
                  return True
              return super().has_permission(request, view)

      class LoginNotRequiredOpen(AuthPermission):
          def has_permission(self, request, view):
              if not settings.LOGIN_REQUIRED:
                  return True
              return super().has_permission(request, view)

      class MyModelPerms(DjangoModelPermissions):
          authenticated_users_only = False

          def has_permission(self, request, view):
              if not request.user.is_authenticated:
                  return False
              return super().has_permission(request, view)
      PY
    File.write(views, <<-PY)
      class SafeViewSet(viewsets.ViewSet):
          permission_classes = [SafeOpen]

      class SettingViewSet(viewsets.ViewSet):
          permission_classes = [LoginNotRequiredOpen]

      class MPViewSet(viewsets.ViewSet):
          permission_classes = [MyModelPerms]
      PY
    [perms, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      safe_read = at.call("GET", 1)
      safe_write = at.call("POST", 1)
      setting = at.call("GET", 4)
      model_perms = at.call("GET", 7)

      DjangoAuthTagger.new(noir_options).perform([safe_read, safe_write, setting, model_perms])

      safe_read.tags.should be_empty
      safe_write.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
      setting.tags.map(&.description).should eq(["Protected by DRF permission_classes (settings.LOGIN_REQUIRED decides; a setting can make it public)"])
      # Its own body refuses anonymous callers before the flag matters.
      model_perms.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "judges composed DRF permissions with grouping, helper refusals and non-Permission bases" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_drf_composed_perms")
    Dir.mkdir_p(tmpdir)
    perms = File.join(tmpdir, "perms.py")
    views = File.join(tmpdir, "views.py")
    File.write(perms, <<-PY)
      def in_group(request, groups):
          if not request.user.is_authenticated:
              return False
          return request.user.groups.filter(name__in=groups).exists()

      def lenient(request):
          if settings.OPEN:
              return True
          if not request.user.is_authenticated:
              return False
          return True

      class IsMember(BasePermission):
          def has_permission(self, request, view):
              return in_group(request, ["member"])

      class Lenient(BasePermission):
          def has_permission(self, request, view):
              return lenient(request)

      class ReadOnly(BasePermission):
          def has_permission(self, request, view):
              return request.method in SAFE_METHODS

      class TokenScope(TokenHasScope):
          def has_permission(self, request, view):
              if isinstance(request.auth, AccessToken):
                  return super().has_permission(request, view)
              return request.user.is_authenticated

      class TokenOptional(TokenHasScope):
          def has_permission(self, request, view):
              if isinstance(request.auth, AccessToken):
                  return super().has_permission(request, view)
              return True
      PY
    File.write(views, <<-PY)
      class MemberViewSet(viewsets.ViewSet):
          permission_classes = [IsMember & TokenOptional]

      class LenientViewSet(viewsets.ViewSet):
          permission_classes = [Lenient]

      class GroupedViewSet(viewsets.ViewSet):
          permission_classes = [(ReadOnly | IsMember) & TokenScope]

      class EitherViewSet(viewsets.ViewSet):
          permission_classes = [(ReadOnly & IsMember) | TokenOptional]

      class NotViewSet(viewsets.ViewSet):
          permission_classes = [~ReadOnly]
      PY
    [perms, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      member = at.call("GET", 1)
      lenient = at.call("GET", 4)
      grouped = at.call("GET", 7)
      either = at.call("POST", 10)
      inverted = at.call("POST", 13)

      DjangoAuthTagger.new(noir_options).perform([member, lenient, grouped, either, inverted])

      # The helper refuses an anonymous caller before anything else.
      member.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
      # This one may let it through first.
      lenient.tags.should be_empty
      # `TokenScope` refuses whatever the grouped alternative allows.
      grouped.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
      # An alternative that lets anonymous through opens the whole `|`.
      either.tags.should be_empty
      inverted.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads a project middleware's refusal and its exempt paths by definition" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_scope_middleware")
    Dir.mkdir_p(File.join(tmpdir, "proj"))
    Dir.mkdir_p(File.join(tmpdir, "app"))
    File.write(File.join(tmpdir, "manage.py"), "")
    File.write(File.join(tmpdir, "proj", "__init__.py"), "")
    File.write(File.join(tmpdir, "proj", "urls.py"), "urlpatterns = []\n")
    settings = File.join(tmpdir, "proj", "settings.py")
    middleware = File.join(tmpdir, "app", "middleware.py")
    soft = File.join(tmpdir, "app", "soft.py")
    views = File.join(tmpdir, "app", "views.py")
    File.write(settings, <<-PY)
      ROOT_URLCONF = "proj.urls"
      PUBLIC_PREFIXES = ["/health"]

      MIDDLEWARE = [
          "django.contrib.auth.middleware.AuthenticationMiddleware",
          "app.middleware.LoginWall",
          "app.soft.SoftWall",
      ]
      PY
    File.write(middleware, <<-'PY')
      import re

      class LoginWall:
          def __init__(self, get_response):
              self.get_response = get_response

          def __call__(self, request):
              prefix = settings.SCRIPT_NAME or ''
              OPEN = ['/login', '/static/', '/beta/']
              if settings.DEBUG:
                  OPEN.append('/__debug__/')
              if request.user.is_authenticated:
                  return self.get_response(request)
              if re.search(r'/share/\d+/', request.path) and request.GET.get('key'):
                  return self.get_response(request)
              for path in OPEN:
                  if request.path.startswith(prefix + path):
                      return self.get_response(request)
              if any(request.path.startswith(p) for p in settings.PUBLIC_PREFIXES):
                  return self.get_response(request)
              if request.path.startswith('/api/'):
                  return JsonResponse({'detail': 'no'}, status=403)
              return HttpResponseRedirect('/login/?next=' + request.path)
      PY
    File.write(soft, <<-PY)
      class SoftWall(MiddlewareMixin):
          def process_request(self, request):
              if request.path.startswith('/beta/') and not request.user.is_authenticated:
                  if settings.BETA_OPEN:
                      return None
                  return redirect_to_login(request.get_full_path())
      PY
    File.write(views, <<-PY)
      def index(request):
          return None
      PY
    [settings, middleware, soft, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(url : String) { Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(views, 1))) }
      home = at.call("/")
      api = at.call("/api/items/<int:pk>/")
      login = at.call("/login/")
      debug = at.call("/__debug__/")
      health = at.call("/health/")
      shared = at.call("/share/<int:pk>/")
      catch_all = at.call("/<path:resource>")
      beta = at.call("/beta/<slug:page>")

      DjangoAuthTagger.new(noir_options).perform([home, api, login, debug, health, shared, catch_all, beta])

      wall = "Protected by LoginWall (settings.MIDDLEWARE refuses unauthenticated requests outside its exempt paths)"
      home.tags.map(&.description).should eq([wall])
      api.tags.map(&.description).should eq([wall])
      # Exempt by its list, the list a setting adds to, a settings list,
      # and a caller-supplied query parameter on a matching path.
      login.tags.should be_empty
      debug.tags.should be_empty
      health.tags.should be_empty
      shared.tags.should be_empty
      # A `<path:...>` route serves exempt paths too.
      catch_all.tags.should be_empty
      # A setting decides: the guard stays, saying so.
      beta.tags.map(&.description).should eq(["Protected by SoftWall (settings.MIDDLEWARE; `settings.BETA_OPEN` decides; a setting can make it public)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  # One Django project per case: `settings` (after ROOT_URLCONF), the
  # `app.middleware.Wall` source, and what each GET endpoint (a view in
  # `app/views.py`) is tagged with: "" for nothing, else a substring.
  middleware_case = ->(settings : String, wall : String, expect : Hash(String, String)) do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_mw_case")
    begin
      Dir.mkdir_p(File.join(tmpdir, "proj"))
      Dir.mkdir_p(File.join(tmpdir, "app"))
      File.write(File.join(tmpdir, "manage.py"), "")
      File.write(File.join(tmpdir, "proj", "__init__.py"), "")
      File.write(File.join(tmpdir, "proj", "urls.py"), "urlpatterns = []\n")
      File.write(File.join(tmpdir, "proj", "settings.py"), "ROOT_URLCONF = \"proj.urls\"\n#{settings}\n")
      File.write(File.join(tmpdir, "app", "middleware.py"), wall)
      views = File.join(tmpdir, "app", "views.py")
      File.write(views, "def index(request):\n    return None\n")
      Dir.glob("#{tmpdir}/**/*.py").each { |path| CodeLocator.instance.register_path(path) }
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      endpoints = expect.keys.map { |url| Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(views, 1))) }
      DjangoAuthTagger.new(noir_options).perform(endpoints)
      endpoints.each do |endpoint|
        want = expect[endpoint.url]
        if want.empty?
          endpoint.tags.should be_empty
        else
          endpoint.tags.size.should eq(1)
          endpoint.tags[0].description.should contain(want)
        end
      end
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
  installed = "MIDDLEWARE = [\"app.middleware.Wall\"]"
  sure = "refuses unauthenticated requests outside its exempt paths"
  unsure = "which this cannot tell"

  it "treats only the request path itself as the path a middleware tests" do
    # A transformed path (`lstrip`, `[1:]`, `split`) is not the path: the
    # guard stays, saying the exemption cannot be read.
    middleware_case.call(installed, <<-PY, {"/api/x/" => unsure, "/home/" => unsure})
      EXEMPT = ["api/"]
      class Wall:
          def __call__(self, request):
              path = request.path_info.lstrip("/")
              if not request.user.is_authenticated:
                  if not any(path.startswith(u) for u in EXEMPT):
                      return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
    middleware_case.call(installed, <<-PY, {"/api/x/" => unsure, "/home/" => unsure})
      class Wall:
          def __call__(self, request):
              if request.path[1:].startswith("api/"):
                  return self.get_response(request)
              if not request.user.is_authenticated:
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
    # A local holding exactly the path is the path.
    middleware_case.call(installed, <<-PY, {"/api/x/" => "", "/home/" => sure})
      EXEMPT = ("/api/",)
      class Wall:
          def __call__(self, request):
              path = request.path_info
              if not request.user.is_authenticated and not path.startswith(tuple(EXEMPT)):
                  return HttpResponseRedirect(settings.LOGIN_URL)
              return self.get_response(request)
      PY
  end

  it "reads only bare string literals as a middleware's exempt paths" do
    middleware_case.call(installed, <<-PY, {"/login/" => unsure, "/home/" => unsure})
      class Wall:
          def __call__(self, request):
              if request.path in [reverse("login")]:
                  return self.get_response(request)
              if not request.user.is_authenticated:
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
    middleware_case.call(installed, <<-PY, {"/open/" => unsure})
      OPEN = (os.environ.get("OPEN_PATHS", "/open/").split(","))
      class Wall:
          def __call__(self, request):
              if not request.user.is_authenticated and not any(request.path.startswith(p) for p in OPEN):
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
  end

  it "says when a setting decides a middleware guard, and drops one the view runs before" do
    middleware_case.call("import os\nMIDDLEWARE = []\nif os.environ.get('PRIVATE'):\n    MIDDLEWARE += ['app.middleware.Wall']", <<-PY, {"/home/" => "installs it only on a condition; a setting can make it public"})
      class Wall:
          def __call__(self, request):
              if not request.user.is_authenticated:
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
    middleware_case.call(installed, <<-PY, {"/home/" => "`not settings.LOGIN_REQUIRED` decides; a setting can make it public"})
      class Wall:
          def __call__(self, request):
              if not settings.LOGIN_REQUIRED:
                  return self.get_response(request)
              if not request.user.is_authenticated:
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
    # The response is built first: the refusal only replaces it.
    middleware_case.call(installed, <<-PY, {"/home/" => ""})
      class Wall:
          def __call__(self, request):
              response = self.get_response(request)
              if not request.user.is_authenticated:
                  return HttpResponseRedirect("/login/")
              return response
      PY
    # An anonymous caller sends no API token.
    middleware_case.call(installed, <<-PY, {"/home/" => sure})
      class Wall:
          def __call__(self, request):
              if not request.user.is_authenticated and "HTTP_X_API_TOKEN" not in request.META:
                  return HttpResponseRedirect("/login/")
              return self.get_response(request)
      PY
  end

  it "applies a middleware only to the project whose settings install it" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_mw_monorepo")
    begin
      {"a_svc" => true, "b_svc" => false}.each do |svc, refuses|
        %w[proj core app].each { |dir| Dir.mkdir_p(File.join(tmpdir, svc, dir)) }
        File.write(File.join(tmpdir, svc, "proj", "__init__.py"), "")
        File.write(File.join(tmpdir, svc, "proj", "urls.py"), "urlpatterns = []\n")
        File.write(File.join(tmpdir, svc, "proj", "settings.py"), "ROOT_URLCONF = \"proj.urls\"\nMIDDLEWARE = [\"core.middleware.Wall\"]\n")
        File.write(File.join(tmpdir, svc, "app", "views.py"), "def index(request):\n    return None\n")
        body = refuses ? "        if not request.user.is_authenticated:\n            return HttpResponseRedirect('/login/')\n" : ""
        File.write(File.join(tmpdir, svc, "core", "middleware.py"), "class Wall:\n    def __call__(self, request):\n#{body}        return self.get_response(request)\n")
      end
      Dir.glob("#{tmpdir}/**/*.py").each { |path| CodeLocator.instance.register_path(path) }
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      a = Endpoint.new("/a/", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "a_svc", "app", "views.py"), 1)))
      b = Endpoint.new("/b/", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "b_svc", "app", "views.py"), 1)))
      DjangoAuthTagger.new(noir_options).perform([a, b])
      a.tags.map(&.description).should eq(["Protected by Wall (settings.MIDDLEWARE #{sure})"])
      b.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "judges a permission helper only when it is the whole verdict, and same-named classes only when they agree" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("django_drf_helper_scope")
    Dir.mkdir_p(tmpdir)
    perms = File.join(tmpdir, "perms.py")
    other = File.join(tmpdir, "other.py")
    views = File.join(tmpdir, "views.py")
    File.write(perms, <<-PY)
      def in_group(request, groups):
          if not request.user.is_authenticated:
              return False
          return True

      class GroupOrList(BasePermission):
          def has_permission(self, request, view):
              return in_group(request, ["user"]) or view.action == "list"

      class GroupOnPost(BasePermission):
          def has_permission(self, request, view):
              if request.method == "POST":
                  return in_group(request, ["user"])
              return True

      class Gate(BasePermission):
          def has_permission(self, request, view):
              return True

      class RecipeLike(BasePermission):
          def has_permission(self, request, view):
              share = request.query_params.get("share")
              return ((in_group(request, ["guest"]) and request.method in SAFE_METHODS) or in_group(
                  request, ["user"])) or (share and request.method in SAFE_METHODS)
      PY
    File.write(other, <<-PY)
      class Gate(object):
          def has_permission(self, request, view):
              return request.user.is_staff
      PY
    File.write(views, <<-PY)
      class AViewSet(viewsets.ViewSet):
          permission_classes = [GroupOrList]

      class BViewSet(viewsets.ViewSet):
          permission_classes = [GroupOnPost]

      class CViewSet(viewsets.ViewSet):
          permission_classes = [Gate]

      class DViewSet(viewsets.ViewSet):
          permission_classes = [RecipeLike]
      PY
    [perms, other, views].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(method : String, line : Int32) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(views, line))) }
      endpoints = [at.call("POST", 1), at.call("POST", 4), at.call("GET", 7)]
      # The whole `or` / `and` return, read per verb: a share link opens
      # reads; a write needs a group an anonymous caller is never in.
      recipe_read = at.call("GET", 10)
      recipe_write = at.call("PUT", 10)
      DjangoAuthTagger.new(noir_options).perform(endpoints + [recipe_read, recipe_write])
      endpoints.each(&.tags.should(be_empty))
      recipe_read.tags.should be_empty
      recipe_write.tags.map(&.description).should eq(["Protected by DRF permission_classes"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
end
