from django.urls import include, path, re_path
from rest_framework.routers import DefaultRouter
from django.views.decorators.cache import cache_page

from . import imported_urls as imported_blog_urls
from . import views
from .api_router import api_router, direct_imported_router as imported_direct_router

app_name = "blog"
router = DefaultRouter()
router.register(r'articles', views.ArticleViewSet, basename='article')
router.register(r'media', views.MediaViewSet, basename='media')
router.register(prefix=r'keyword-media', viewset=views.MediaViewSet, basename='keyword-media')
# router.register(r'commented-media', views.MediaViewSet, basename='commented-media')
direct_router = DefaultRouter()
direct_router.register(r'direct-articles', views.ArticleViewSet, basename='direct-article')

local_patterns = [
    path(
        'reports/',
        views.local_report_list,
        name='local_report_list'),
    path(
        'reports/<slug:report_slug>/',
        views.local_report_detail,
        name='local_report_detail'),
]

namespace_patterns = [
    path(
        'exports/',
        views.local_export,
        name='local_export'),
]

base_patterns = [
    path(
        'combined/',
        views.combined_report,
        name='combined_report'),
]

extended_patterns = [
    path(
        'extended/',
        views.extended_report,
        name='extended_report'),
]

urlpatterns = [
    # path('commented/', views.local_report_list, name='commented'),
    path('api/', include(router.urls)),
    path('imported-api/', include(api_router.urls)),
    path('module-include/', include(imported_blog_urls)),
    path('local/', include(local_patterns)),
    path('namespaced/', include((namespace_patterns, app_name), namespace='nested')),
    path(
        r'',
        views.IndexView.as_view(),
        name='index'),
    path(
        r'page/<int:page>/',
        views.IndexView.as_view(),
        name='index_page'),
    path(
        r'article/<int:year>/<int:month>/<int:day>/<int:article_id>.html',
        views.ArticleDetailView.as_view(),
        name='detailbyid'),
    path(
        r'category/<slug:category_name>.html',
        views.CategoryDetailView.as_view(),
        name='category_detail'),
    path(
        r'category/<slug:category_name>/<int:page>.html',
        views.CategoryDetailView.as_view(),
        name='category_detail_page'),
    path(
        r'author/<author_name>.html',
        views.AuthorDetailView.as_view(),
        name='author_detail'),
    path(
        r'author/<author_name>/<int:page>.html',
        views.AuthorDetailView.as_view(),
        name='author_detail_page'),
    path(
        r'tag/<slug:tag_name>.html',
        views.TagDetailView.as_view(),
        name='tag_detail'),
    path(
        r'tag/<slug:tag_name>/<int:page>.html',
        views.TagDetailView.as_view(),
        name='tag_detail_page'),
    path(
        'archives.html',
        cache_page(
            60 * 60)(
            views.ArchivesView.as_view()),
        name='archives'),
    path(
        'links.html',
        views.LinkListView.as_view(),
        name='links'),
    path(
        'feedback/',
        views.FeedbackView.as_view(),
        name='feedback'),
    path(
        r'upload',
        views.fileupload,
        name='upload'),
    path(
        r'not_found',
        views.page_not_found_view,
        name='page_not_found_view'),
    path(
        r'test',
        views.test,
        name='test'),
    path(
        r'delete_test',
        views.delete_test,
        name='delete_test'),
    path(
        r'require_post',
        views.require_post_view,
        name='require_post_view'),
    path(
        r'require_methods',
        views.require_methods_view,
        name='require_methods_view'),
    path(
        r'widget/delete',
        views.WidgetDeleteView.as_view(),
        name='widget_delete'),
    path(
        r'api/token/',
        views.ApiTokenView.as_view(),
        name='api_token'),
    path(
        r'api/account/',
        views.AccountRetrieveUpdateAPIView.as_view(),
        name='api_account'),
    re_path(
        r'^legacy/(?P<legacy_id>[0-9]+)/$',
        views.legacy_detail,
        name='legacy_detail'),
    re_path(
        r'^nested/(?P<nested_slug>[\w-]+(/[\w-]+)*)_(?P<pk>\d+)/$',
        views.nested_regex_detail,
        name='nested_regex_detail'),
]
urlpatterns = base_patterns + urlpatterns
urlpatterns.extend(extended_patterns)
urlpatterns.extend(
    direct_router.urls
)
urlpatterns += imported_direct_router.urls
