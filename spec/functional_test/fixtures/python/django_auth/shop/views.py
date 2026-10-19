from django.views.generic import TemplateView


class SummaryView(TemplateView):
    template_name = "shop/summary.html"


class SavedView(TemplateView):
    template_name = "shop/saved.html"
