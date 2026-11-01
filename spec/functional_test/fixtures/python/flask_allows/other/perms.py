class Allows:
    """A project's own rate-limit bucket, not flask_allows."""

    def requires(self, *names):
        def wrap(f):
            return f

        return wrap


allows = Allows()
