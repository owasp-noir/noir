# Powertools utilities without the event handler are not REST routing.
from aws_lambda_powertools import Logger, Tracer
from mylib import Api

logger = Logger()
tracer = Tracer()
api = Api()


@api.get("/phantom")
@tracer.capture_method
def phantom():
    return "no"
