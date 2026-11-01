import os


class DefaultConfig:
    USER_URL_PREFIX = "/user"
    ADMIN_URL_PREFIX = "/admin"
    MESSAGE_URL_PREFIX = os.environ.get("MESSAGE_URL_PREFIX", "/message")


class TestingConfig(DefaultConfig):
    USER_URL_PREFIX = "/test-user"


class ProductionConfig(DefaultConfig):
    API_URL_PREFIX = "/api"


class DevelopmentConfig(DefaultConfig):
    API_URL_PREFIX = "/dev-api"
