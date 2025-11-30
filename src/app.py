import asyncio
import logging
import os
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

import uvicorn
from fastapi import BackgroundTasks, FastAPI

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
    logger.info("Scanning Tool Version %s", os.getenv("VERSION", "unspecified (dev)"))
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


async def start_scan(outfile: Path) -> None:
    logger.info("starting scan")
    outfile.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(ignore_cleanup_errors=True) as directory:
        d = Path(directory)
        stdout, stderr = await run(
            f"cd {d.absolute()} && "
            f"scanimage --format=tiff --batch='scan.page-%03d.tiff' -x 210 -y 297 && "
            "convert *.tiff scan.pdf",
        )
        if stdout:
            logger.info("stdout:\n%s", stdout)
        if stderr:
            logger.info("stderr:\n%s", stderr)
        logger.info(", ".join(f.name for f in d.glob("*")))
        logger.info("finished scan")
        outfile.write_bytes((d / "scan.pdf").read_bytes())
        logger.info("copied scan to %s", outfile)


@app.get("/scan")
async def scan(
    *,
    double_sided: bool = False,
    tags: list[str] | None = None,
    background_tasks: BackgroundTasks,
) -> dict[str, str]:
    filename = f"SCAN_{datetime.now(tz=UTC).strftime('%Y-%m-%d_%H-%M-%S')}.pdf"
    if double_sided:
        filename = "double-sided/" + filename
    if tags:
        filename = f"{'/'.join(tags)}/{filename}"
    outfile = Path("/scans") / filename
    background_tasks.add_task(start_scan, outfile)
    return {"file": filename}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)  # noqa: S104
