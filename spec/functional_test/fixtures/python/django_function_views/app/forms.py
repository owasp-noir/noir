from django import forms


class FilterForm(forms.Form):
    start = forms.IntegerField(required=False)


class SearchForm(FilterForm):
    q = forms.CharField()


class LoginForm(forms.Form):
    email = forms.EmailField()
    password = forms.CharField()
