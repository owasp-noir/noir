from django import forms

from .models import Article


class LoginForm(forms.Form):
    email = forms.EmailField()
    password = forms.CharField()

    def clean(self):
        cleaned = super().clean()
        cleaned["user"] = None
        return cleaned


class ArticleForm(forms.ModelForm):
    class Meta:
        model = Article
        fields = "__all__"


class OtpForm(forms.Form):
    email = forms.EmailField()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["otp"] = forms.CharField()
