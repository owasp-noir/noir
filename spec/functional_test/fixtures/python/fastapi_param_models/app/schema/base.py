from pydantic import BaseModel, ConfigDict


def camelize(value: str) -> str:
    head, *rest = value.split("_")
    return head + "".join(part.title() for part in rest)


class AppModel(BaseModel):
    model_config = ConfigDict(alias_generator=camelize, populate_by_name=True)
