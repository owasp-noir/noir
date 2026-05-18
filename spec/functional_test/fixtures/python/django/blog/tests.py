# Regression guard: a `tests.py` file inside a Django app has its own
# `ROOT_URLCONF` to spin up a self-contained test project, but the
# routes it registers should NEVER surface as endpoints — they only
# serve the test suite. The expected-endpoints list in the spec does
# not include `/should-not-appear-test`.
from django.urls import path
from django.test import TestCase

ROOT_URLCONF = "blog.tests"

urlpatterns = [
    path("should-not-appear-test", lambda r: None),
    path("should-not-appear-test-2", lambda r: None),
]


class SmokeTest(TestCase):
    def test_noop(self):
        self.assertTrue(True)
