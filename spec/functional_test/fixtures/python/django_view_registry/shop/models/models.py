from django.db import models


# Declared in `shop/models/models.py`: the app label is still `shop`.
class Widget(models.Model):
    name = models.CharField(max_length=10)
