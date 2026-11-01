def requires(*scopes):
    """An OAuth scope note for the docs; checks nothing."""

    def deco(f):
        return f

    return deco
