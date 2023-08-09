require "../../src/analyzer/analyzers/analyzer_django.cr"
require "../../src/options"

describe "mapping_to_path" do
  options = default_options()
  instance = AnalyzerDjango.new(options)

  it "mapping_to_path - code style1" do
    instance.mapping_to_path("path('home/', views.home_view, name='home'),").should eq(["/home/"])
  end

  it "mapping_to_path - code style2" do
    instance.mapping_to_path("path('articles/<int:pk>/', views.article_detail_view, name='article_detail'),").should eq(["/articles/<int:pk>/"])
  end

  it "mapping_to_path - code style3 (regex)" do
    instance.mapping_to_path("re_path(r'^archive/(?P<year>d{4})/$', views.archive_year_view, name='archive_year'),").should eq(["/archive/(?P<year>d{4})/"])
  end

  it "mapping_to_path - code style4 (register)" do
    instance.mapping_to_path("router.register(r'articles', ArticleViewSet)").should eq(["/articles"])
  end
end
