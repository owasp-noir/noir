from django.contrib.auth.decorators import login_required


@login_required
def detail(request, pk):
    return None
