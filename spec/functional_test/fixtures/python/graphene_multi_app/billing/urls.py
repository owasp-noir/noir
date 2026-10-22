from django.urls import path
from graphene_django.views import GraphQLView

urlpatterns = [
    path("billing/graphql/", GraphQLView.as_view()),
]
