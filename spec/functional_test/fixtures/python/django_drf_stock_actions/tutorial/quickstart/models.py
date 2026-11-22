from django.db import models


class Group(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=40)
    capacity = models.PositiveIntegerField(default=1)
    color = models.CharField(max_length=20)
    modified = models.DateTimeField(auto_now=True)
    checksum = models.CharField(max_length=20, editable=False)
    note = models.TextField()

    @property
    def display_name(self):
        return self.name.title()
