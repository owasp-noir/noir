from flask_restful import reqparse

search_parser = reqparse.RequestParser()
search_parser.add_argument("term", location="args")
search_parser.add_argument(
    "limit",
    type=int,
    location=("args",),
)

paged_parser = search_parser.copy()
paged_parser.add_argument("cursor", location="args")
