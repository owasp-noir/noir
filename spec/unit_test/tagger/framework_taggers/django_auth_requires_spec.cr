require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` under a temp dir, tags the endpoint whose code path is
# `file` at `line`, and returns its `django_auth` tags.
private def django_tags(files : Hash(String, String), file : String, line : Int32, method : String = "GET", url : String = "/x") : Array(Tag)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("django_requires")
  files.each do |name, source|
    path = File.join(tmpdir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(File.join(tmpdir, file), line))
  details.technology = "python_django"
  endpoint = DjangoAuthTagger.new(options).perform([Endpoint.new(url, method, [] of Param, details)])[0]
  endpoint.tags.select(&.tagger.==("django_auth"))
ensure
  FileUtils.rm_rf(tmpdir) if tmpdir
  CodeLocator.instance.clear_all
end

private def atoms(tag : Tag) : Array(Array(String))
  (tag.requires || [] of Access::Clause).map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s })
end

describe "DjangoAuthTagger requires" do
  it "joins every decorator stacked on a function view, the nearest naming the tag" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 3)
      @login_required
      @permission_required(["blog.add_post", "blog.publish_post"])
      def create(request):
          pass
      PY
    tags.size.should eq(1)
    tags[0].description.should eq("Protected by Django permission_required decorator")
    # One clause per layer: each records its own source.
    atoms(tags[0]).should eq([["authenticated"], ["permission:blog.add_post"], ["permission:blog.publish_post"], ["authenticated"]])
    tags[0].requires.not_nil!.map(&.source).uniq!.should eq(["@permission_required([\"blog.add_post\", \"blog.publish_post\"])", "@login_required"])
  end

  it "reads permission_required arguments that wrap onto the next lines" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 4)
      @permission_required(
          "blog.change_post",
      )
      def edit(request):
          pass
      PY
    atoms(tags[0]).should eq([["authenticated"], ["permission:blog.change_post"]])
  end

  it "keeps a user_passes_test check unresolved, signed in or not" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 2)
      @user_passes_test(lambda u: u.is_superuser)
      def purge(request):
          pass
      PY
    atoms(tags[0]).should eq([["unresolved:@user_passes_test(lambda u: u.is_superuser)"]])
  end

  it "reads staff_member_required as signed in plus an unread is_staff" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 2)
      @staff_member_required
      def report(request):
          pass
      PY
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:is_staff"]])
  end

  it "does not read a project decorator named like Django's as Django's" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 6)
      def login_required(view):
          return view

      @login_required
      def dashboard(request):
          pass
      PY
    tags[0].description.should eq("Protected by Django login_required decorator")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:Protected by Django login_required decorator"]])
  end

  it "joins a handler's method_decorator with the class's permission mixin" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 11)
      from django.contrib.auth.mixins import PermissionRequiredMixin
      from django.views import View

      class EditView(PermissionRequiredMixin, View):
          permission_required = (
              "blog.view_post",
              "blog.change_post",
          )

          @method_decorator([never_cache, login_required])
          def get(self, request):
              pass
      PY
    tags[0].description.should eq("Protected by Django login_required decorator")
    atoms(tags[0]).should eq([["authenticated"], ["authenticated"], ["permission:blog.view_post"], ["permission:blog.change_post"]])
  end

  it "reads each auth mixin in the MRO, and an overridden has_permission as unresolved" do
    files = {"views.py" => <<-PY}
      from django.contrib.auth.mixins import LoginRequiredMixin, PermissionRequiredMixin
      from django.views import View

      class OwnView(LoginRequiredMixin, PermissionRequiredMixin, View):
          def has_permission(self):
              return self.request.user.pk == 1

          def get(self, request):
              pass
      PY
    tags = django_tags(files, "views.py", 8)
    tags[0].description.should eq("Protected by Django LoginRequiredMixin")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:OwnView.has_permission"]])
  end

  it "reads a UserPassesTestMixin view's test, not a sign-in" do
    tags = django_tags({"views.py" => <<-PY}, "views.py", 8)
      from django.contrib.auth.mixins import UserPassesTestMixin
      from django.views import View

      class SuperView(UserPassesTestMixin, View):
          def test_func(self):
              return self.request.user.is_superuser

          def get(self, request):
              pass
      PY
    atoms(tags[0]).should eq([["unresolved:self.request.user.is_superuser"]])
  end

  it "reads DRF permission_classes per class and per verb" do
    files = {"views.py" => <<-PY}
      from rest_framework.views import APIView

      class NoteView(APIView):
          permission_classes = [IsAuthenticatedOrReadOnly, IsOwner | IsAdminUser]

          def post(self, request):
              pass
      PY
    tags = django_tags(files, "views.py", 6, "POST")
    tags[0].description.should eq("Protected by DRF permission_classes")
    atoms(tags[0]).should eq([["authenticated"], ["authenticated", "unresolved:IsOwner"], ["unresolved:IsOwner", "unresolved:is_staff"]])
  end

  it "lets each DRF permission list replace the one it overrides" do
    views = <<-PY
      from rest_framework import viewsets
      from rest_framework.views import APIView

      class ItemViewSet(viewsets.ModelViewSet):
          permission_classes = [IsAdminUser]

          @action(detail=False, permission_classes=[IsAuthenticated])
          def mine(self, request):
              pass

      class PingView(APIView):
          permission_classes = [IsAuthenticated]

          def get(self, request):
              pass

      @api_view(["GET"])
      @permission_classes([IsAuthenticated])
      def health(request):
          pass
      PY
    files = {
      "settings.py" => %(REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAdminUser"]}\n),
      "views.py"    => views,
    }
    # The action, the view over the default, and `@permission_classes`.
    [8, 14, 19].each do |line|
      tags = django_tags(files, "views.py", line)
      tags[0].description.should eq("Protected by DRF permission_classes")
      atoms(tags[0]).should eq([["authenticated"]])
    end
  end

  it "keeps LoginRequiredMiddleware on a DRF view unread, since DRF 3.16 exempts its views" do
    files = {
      "settings.py" => %(MIDDLEWARE = ["django.contrib.auth.middleware.LoginRequiredMiddleware"]\n),
      "views.py"    => "from rest_framework.views import APIView\n\nclass KeyView(APIView):\n    permission_classes = [HasAPIKey]\n\n    def get(self, request):\n        pass\n",
    }
    tags = django_tags(files, "views.py", 6)
    tags[0].description.should eq("Protected by DRF permission_classes")
    atoms(tags[0]).should eq([["unresolved:HasAPIKey"], ["authenticated", "unresolved:DRF 3.16+ exempts its views from LoginRequiredMiddleware"]])
  end

  it "keeps only what disagreeing DEFAULT_PERMISSION_CLASSES share" do
    files = {
      "proj/settings/base.py" => %(REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"]}\n),
      "proj/settings/prod.py" => %(REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAdminUser"]}\n),
      "proj/views.py"         => "class ItemViewSet(viewsets.ModelViewSet):\n    queryset = None\n",
    }
    tags = django_tags(files, "proj/views.py", 1)
    tags[0].description.should eq("Protected by DRF DEFAULT_PERMISSION_CLASSES")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:DEFAULT_PERMISSION_CLASSES differs between settings modules"]])
  end

  it "adds LoginRequiredMiddleware to a view guard it does not imply" do
    files = {
      "settings.py" => %(MIDDLEWARE = ["django.contrib.auth.middleware.LoginRequiredMiddleware"]\n),
      "views.py"    => "@user_passes_test(is_editor)\ndef edit(request):\n    pass\n",
    }
    tags = django_tags(files, "views.py", 2)
    tags.size.should eq(1)
    tags[0].description.should eq("Protected by Django user_passes_test decorator")
    atoms(tags[0]).should eq([["unresolved:@user_passes_test(is_editor)"], ["authenticated"]])
  end

  it "gives a project guard the explicit signed-in-plus-unread reading" do
    files = {"views.py" => <<-PY}
      from django.http import HttpResponseForbidden

      def staff_only(view):
          def wrapper(request, *args, **kwargs):
              if not request.user.is_authenticated:
                  return HttpResponseForbidden()
              return view(request, *args, **kwargs)
          return wrapper

      @staff_only
      def report(request):
          pass
      PY
    tags = django_tags(files, "views.py", 11)
    tags[0].description.should eq("Protected by staff_only")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:Protected by staff_only"]])
  end

  it "adds a project middleware's requirement to a guarded view, lifting it where a setting decides" do
    middleware = <<-PY
      class Wall:
          def __init__(self, get_response):
              self.get_response = get_response

          def __call__(self, request):
              if request.path.startswith("/beta/") and settings.BETA_OPEN:
                  return self.get_response(request)
              if request.user.is_authenticated or request.path.startswith("/login/"):
                  return self.get_response(request)
              return HttpResponseRedirect("/login/")
      PY
    files = {
      "manage.py"         => "",
      "proj/__init__.py"  => "",
      "proj/urls.py"      => "urlpatterns = []\n",
      "proj/settings.py"  => %(ROOT_URLCONF = "proj.urls"\nMIDDLEWARE = ["app.middleware.Wall"]\n),
      "app/middleware.py" => middleware,
      "app/views.py"      => "def index(request):\n    pass\n\n@user_passes_test(is_editor)\ndef edit(request):\n    pass\n",
    }
    open = django_tags(files, "app/views.py", 1)
    open[0].description.should eq("Protected by Wall (settings.MIDDLEWARE refuses unauthenticated requests outside its exempt paths)")
    atoms(open[0]).should eq([["authenticated"]])

    guarded = django_tags(files, "app/views.py", 5)
    guarded.size.should eq(1)
    guarded[0].description.should eq("Protected by Django user_passes_test decorator")
    atoms(guarded[0]).should eq([["unresolved:@user_passes_test(is_editor)"], ["authenticated"]])

    beta = django_tags(files, "app/views.py", 1, url: "/beta/")
    beta[0].description.should contain("a setting can make it public")
    atoms(beta[0]).should eq([["authenticated", "unresolved:#{beta[0].description}"]])
  end

  it "reads the admin site as signed-in staff with model permissions unread" do
    files = {"urls.py" => "urlpatterns = [\n    path(\"admin/\", admin.site.urls),\n]\n"}
    tags = django_tags(files, "urls.py", 2, url: "/admin/")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:is_staff"], ["unresolved:ModelAdmin permissions"]])
  end
end
