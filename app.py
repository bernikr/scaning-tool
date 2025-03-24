import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI

logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, Any]:  # noqa: ARG001, RUF029
    logger.info("Starting application...")
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Hello World"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)  # noqa: S104
