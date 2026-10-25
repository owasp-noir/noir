from functools import partial

from flask import abort, request

MULTI_ORG = False


# Prefixes the rule only when a setting is on: the literal is the default path.
def org_scoped_rule(rule):
    if MULTI_ORG:
        return "/<org_slug>{}".format(rule)
    return rule


# Always rewrites the rule: the literal is never served as written.
def versioned_rule(rule):
    return "/v2" + rule


def _order_results(results, allowed):
    requested = request.args.get("order", "")
    return allowed.get(requested, results)


order_results = partial(_order_results, allowed={})


def require_fields(req, fields):
    for f in fields:
        if f not in req:
            abort(400)
