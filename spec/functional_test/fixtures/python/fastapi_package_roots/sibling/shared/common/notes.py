from pydantic import BaseModel

class NoteIn(BaseModel):
    text: str
