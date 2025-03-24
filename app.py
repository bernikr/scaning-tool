import asyncio
import logging
import os
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal

import uvicorn
from fastapi import FastAPI

logger = logging.getLogger("uvicorn.error")

SCANNER_MODEL_NAME = os.getenv("SCANNER_MODEL_NAME")
SCANNER_IP = os.getenv("SCANNER_IP")


async def run(cmd: str) -> tuple[str, str]:
    process = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    stdout, stderr = await process.communicate()
    return stdout.decode(), stderr.decode()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, Any]:  # noqa: ARG001
    logger.info("removing scanner")
    _, _ = await run("brsaneconfig4 -r scanner")
    logger.info("adding scanner")
    _, _ = await run(f"brsaneconfig4 -a name=scanner model={SCANNER_MODEL_NAME} ip={SCANNER_IP}")
    out, _ = await run("brsaneconfig4 -q")
    logger.info(out)
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Hello World"}


@app.get("/scan")
async def scan(
    *,
    source: Literal["flatbed", "adf-left", "adf"] = "adf",
    double_sided: bool = False,
    tags: list[str] | None = None,
) -> dict[str, str]:
    filename = f"SCAN_{datetime.now(tz=UTC).strftime('%Y-%m-%d_%H-%M-%S')}.pdf"
    if double_sided:
        filename = "double-sided/" + filename
    if tags:
        filename = f"{'/'.join(tags)}/{filename}"
    sources = {
        "flatbed": "FlatBed",
        "adf-left": "Automatic Document Feeder(left aligned)",
        "adf": "Automatic Document Feeder(centrally aligned)",
    }
    logger.info("starting scan %s from source %s", filename, source)
    outfile = Path("/scans") / filename
    outfile.parent.mkdir(parents=True, exist_ok=True)
    logger.info("outfile: %s", outfile)
    _, stderr = await run(
        f"scanimage --format=pdf --source='{sources[source]}' > {outfile.absolute()}",
    )
    logger.info("finished scan")
    return {"file": filename, "source": source, "stderr": stderr}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)  # noqa: S104
