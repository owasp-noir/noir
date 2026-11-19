from django.views import generic


class IndexView(generic.ListView):
    template_name = "polls/index.html"


class DetailView(generic.DetailView):
    template_name = "polls/detail.html"
