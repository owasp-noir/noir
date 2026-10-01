from django.urls import path, register_converter

from . import converters, views

register_converter(converters.FourDigitYearConverter, "yyyy")

urlpatterns = [
    # A registered custom converter is still spelled converter first.
    path("articles/<yyyy:year>/", views.year_archive),
    path("posts/<int:pk>/", views.post_detail),
]
