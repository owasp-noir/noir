# Regression guard: a file under a `tests/` directory should be
# skipped by the analyzer's test-file filter. The Django blog tests.py
# already covers the `tests.py` filename convention; this file covers
# the `tests/` directory convention with a pytest-style `test_*.py`
# filename. None of the URLs below should surface as endpoints.
from django.urls import path

ROOT_URLCONF = "tests.test_views"

urlpatterns = [
    path("should-not-appear-tests-dir", lambda r: None),
    path("should-not-appear-test-prefix", lambda r: None),
]


def test_noop():
    assert True
