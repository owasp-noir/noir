from flask import request


def read_page():
    return request.args.get("page")
