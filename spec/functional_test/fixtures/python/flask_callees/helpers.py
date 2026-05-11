def build_user_query(name):
    return "SELECT * FROM users WHERE name = '%s'" % name


def run_sql_query(sql):
    # placeholder; the analyzer only sees the name being called
    return {"sql": sql}


def notify_admin(user):
    pass


def log_audit(user):
    pass
