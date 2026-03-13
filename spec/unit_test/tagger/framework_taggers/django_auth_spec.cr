require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "DjangoAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/python/django_auth"
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
end
