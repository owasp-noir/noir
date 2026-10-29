from django.db import models


# The module is `order`, the class `Order`: on a case-insensitive file
# system `from .models import Order` must not bind the module.
class Order(models.Model):
    total = models.IntegerField()
