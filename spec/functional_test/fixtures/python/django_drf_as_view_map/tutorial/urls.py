from django.urls import path
from rest_framework.authtoken.views import obtain_auth_token
from rest_framework.urlpatterns import format_suffix_patterns
from rest_framework_simplejwt.views import TokenObtainPairView

from tutorial.snippets import views
from tutorial.snippets.views import SnippetViewSet

# DRF tutorial part 6, "Binding ViewSets to URLs explicitly".
snippet_list = SnippetViewSet.as_view({
    'get': 'list',
    'post': 'create'
})
snippet_detail = SnippetViewSet.as_view({
    'get': 'retrieve',
    'put': 'update',
    'patch': 'partial_update',
    'delete': 'destroy'
})

urlpatterns = format_suffix_patterns([
    path('snippets/', snippet_list, name='snippet-list'),
    path('snippets/<int:pk>/', snippet_detail, name='snippet-detail'),
    path('inline/', SnippetViewSet.as_view({'get': 'list', 'post': 'create'})),
    path('inline/<int:pk>/', SnippetViewSet.as_view({'get': 'retrieve', 'delete': 'destroy'})),
    path('api-token-auth/', obtain_auth_token),
    path('highlight/<int:pk>/', views.snippet_highlight),
    path('api/token/', TokenObtainPairView.as_view()),
])
