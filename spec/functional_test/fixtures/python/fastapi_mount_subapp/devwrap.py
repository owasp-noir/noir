from fastapi import FastAPI

from main import app

# A route-less wrapper in another file: the real app is still served on
# its own, so its routes stay reported at the root as well.
wrapper = FastAPI()
wrapper.mount("/prefixed", app)
