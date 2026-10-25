from django import forms

from .models import Item


class ItemForm(forms.ModelForm):
    note = forms.CharField(required=False)

    class Meta:
        model = Item
        fields = ("name", "price")
