from core.views import register_model_view
from views import generic

from . import forms
from .models import *


@register_model_view(Item, "list", path="", detail=False)
class ItemListView(generic.ObjectListView):
    pass


@register_model_view(Item)
class ItemView(generic.ObjectView):
    pass


@register_model_view(Item, "add", detail=False)
@register_model_view(Item, "edit")
class ItemEditView(generic.ObjectEditView):
    form = forms.ItemForm
