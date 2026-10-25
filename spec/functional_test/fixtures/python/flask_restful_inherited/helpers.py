from functools import partial

from flask import abort, request

from paging import read_page

MULTI_ORG = False


# Prefixes the rule only when a setting is on: the literal is the default path.
def org_scoped_rule(rule):
    if MULTI_ORG:
        return "/<org_slug>{}".format(rule)
    return rule


# Always rewrites the rule: the literal is never served as written.
def versioned_rule(rule):
    return "/v2" + rule


# Rewrites the rule before returning it.
def reassigned_rule(rule):
    rule = "/api" + rule
    return rule


# The unchanged `return rule` belongs to a nested function.
def nested_rule(rule):
    def inner(rule):
        return rule

    return "/v3" + inner(rule)


def _order_results(results, allowed):
    requested = request.args.get("order", "")
    return allowed.get(requested, results)


order_results = partial(_order_results, allowed={})


def paginate():
    return read_page()


def legacy_reader():
    return request.args.get("legacy_token")


def require_fields(req, fields):
    for f in fields:
        if f not in req:
            abort(400)
