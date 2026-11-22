INSTALLED_APPS = ["rest_framework", "tutorial.quickstart"]
ROOT_URLCONF = "tutorial.urls"

REST_FRAMEWORK = {
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "tutorial.quickstart.filters.StableOrder",
    ),
    "SEARCH_PARAM": "term",
    "ORDERING_PARAM": "sort",
    "DEFAULT_PAGINATION_CLASS": "tutorial.quickstart.filters.Pages",
    "PAGE_SIZE": 25,
}

# Similar keys outside REST_FRAMEWORK do not configure the API.
OTHER = {"SEARCH_PARAM": "unused"}
