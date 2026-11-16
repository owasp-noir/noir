from django.db import connection


def find_rows(name):
    cursor = connection.cursor()
    cursor.execute("SELECT * FROM rows WHERE name = '%s'" % name)
    return cursor.fetchall()
