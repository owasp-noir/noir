from flask import Flask, request
from flask_restful import Api, Resource, reqparse

from parsers import paged_parser

app = Flask(__name__)
api = Api(app)

# flask-restful quickstart ("Full example")
parser = reqparse.RequestParser()
parser.add_argument('task')
parser.add_argument('rate', type=int, help='Rate to charge for this resource')
parser.add_argument('page', type=int, location='args')
parser.add_argument('X-Api-Key', location='headers')
parser.add_argument('session_id', location='cookies')
parser.add_argument('picture', location='files')
parser.add_argument('pub_name', dest='public_name', location='form')



class Options:
    def add_argument(self, name):
        pass

    def parse_args(self):
        return {}


# Not a reqparse parser.
cli = Options()
cli.add_argument('verbose')


class TodoList(Resource):
    def get(self):
        args = parser.parse_args()
        return []

    def post(self):
        args = parser.parse_args()
        return {'task': args['task']}, 201


class Todo(Resource):
    def __init__(self):
        self.reqparse = reqparse.RequestParser()
        self.reqparse.add_argument('title', location='json')

    def put(self, todo_id):
        put_parser = reqparse.RequestParser()
        put_parser.add_argument('done', type=bool, required=True)
        args = put_parser.parse_args()
        return {}

    def patch(self, todo_id):
        args = self.reqparse.parse_args()
        return request.form['note']


class Search(Resource):
    def get(self):
        args = paged_parser.parse_args()
        return []


class Cli(Resource):
    def get(self):
        args = cli.parse_args()
        return []


api.add_resource(TodoList, '/todos')
api.add_resource(Todo, '/todos/<todo_id>')
api.add_resource(Search, '/search')
api.add_resource(Cli, '/cli')
