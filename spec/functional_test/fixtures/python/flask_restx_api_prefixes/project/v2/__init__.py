from flask_restx import Api

from .birds import birds_ns
from .fish import fish_ns

rest_api = Api(title="My Title", version="1.0", prefix="/v2")

rest_api.add_namespace(birds_ns)
rest_api.add_namespace(fish_ns, path="/swimmers")
