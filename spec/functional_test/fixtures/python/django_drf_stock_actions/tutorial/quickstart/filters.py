from contextlib import nullcontext
from os import getenv

from django_filters import rest_framework as filters
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.pagination import PageNumberPagination
from rest_framework.settings import api_settings

from .models import Group


class BasePages(PageNumberPagination):
    page_size = 25
    page_query_param = "number"
    page_size_query_param = "count"


class Pages(BasePages):
    page_size_query_param = getenv("API_PAGE_SIZE_PARAM", BasePages.page_size_query_param)


class StableOrder(OrderingFilter):
    ordering_param = getenv("API_ORDERING_PARAM", api_settings.ORDERING_PARAM)


class Unpaged(PageNumberPagination):
    page_size = None


class LabelSearch(SearchFilter):
    def get_search_fields(self, view, request):
        return ("title",)


class BaseGroupFilter(filters.FilterSet):
    nickname = filters.CharFilter(field_name="name", lookup_expr="icontains")

    class Meta:
        model = Group
        fields = {"name": ["exact", "startswith"]}


with nullcontext():
    class GroupFilter(BaseGroupFilter):
        class Meta(BaseGroupFilter.Meta):
            model = Group
