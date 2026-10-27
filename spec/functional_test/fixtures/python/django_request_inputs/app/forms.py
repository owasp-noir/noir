from django import forms


class LoginForm(forms.Form):
    email = forms.EmailField()
    password = forms.CharField()

    def clean(self):
        cleaned = super().clean()
        cleaned["user"] = None
        return cleaned
