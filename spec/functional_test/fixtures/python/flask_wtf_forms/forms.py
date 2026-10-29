from flask_wtf import FlaskForm
from wtforms import Form, StringField, PasswordField, SubmitField


class LoginForm(FlaskForm):
    username = StringField("Username")
    password = PasswordField("Password")
    submit = SubmitField("Sign In")


class BaseForm(
    FlaskForm,
):
    locale = StringField("Locale")


class ProfileForm(BaseForm):
    bio = StringField("Bio")


class PlainForm(Form):
    nickname = StringField("Nickname")


class SearchForm(FlaskForm):
    term = StringField("Term")
