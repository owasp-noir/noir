from pydantic_settings import BaseSettings


class FactorySettings(BaseSettings):
    api_prefix: str = "/factory"
