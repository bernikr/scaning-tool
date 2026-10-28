# SPDX-FileCopyrightText: 2026 bernikr <hi@berni.kr>
#
# SPDX-License-Identifier: MIT

import asyncio
import logging
import os
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import]
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from tempfile import TemporaryDirectory
from typing import Any, Literal
lazy from collections.abc import AsyncGenerator

import httpx
import uvicorn
from anyio import Path
from fastapi import BackgroundTasks, FastAPI, Response

logger = logging.getLogger("uvicorn.error")

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
async def lifespan(app: FastAPI) -> AsyncGenerator[None, Any]:  # ruff: ignore[unused-function-argument]
    logger.info("Scanning Tool Version %s", os.getenv("VERSION", "unspecified (dev)"))
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/hc")
def healthcheck() -> Response:
    return Response("OK", media_type="text/plain")


async def detect_scan_source() -> Literal["Flatbed", "ADF"]:
    try:  # ruff: ignore[too-many-statements-in-try-clause]
        url = f"http://{SCANNER_IP}:80/eSCL/ScannerStatus"
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()

            root = ET.fromstring(resp.content)  # ruff: ignore[suspicious-xml-element-tree-usage]
            adf_state = None
            for elem in root.iter():
                if elem.tag.endswith("AdfState"):
                    adf_state = elem.text
                    break

            if adf_state == "ScannerAdfLoaded":
                return "ADF"
    except Exception as e:  # ruff: ignore[blind-except]
        logger.warning("Could not read ADF sensor status: %s. Defaulting to Flatbed.", e)

    return "Flatbed"


async def start_scan(outfile: Path) -> None:
    logger.info("starting scan")
    await outfile.parent.mkdir(parents=True, exist_ok=True)

    source = await detect_scan_source()
    logger.info("Detected scan source: %s", source)
    batch_count_arg = "--batch-count=1" if source == "Flatbed" else ""

    with TemporaryDirectory(ignore_cleanup_errors=True) as directory:
        d = await Path(directory).absolute()
        stdout, stderr = await run(
            f"cd {d.as_posix()} && "
            f"scanimage -d 'escl:http://{SCANNER_IP}:80' --source '{source}' {batch_count_arg} "
            "--mode Color --resolution 300 "
            "--format=tiff --batch='scan.page-%03d.tiff' -l 0 -t 0 -x 210 -y 297 && "
            "convert -density 300 *.tiff -page A4 -compress jpeg -quality 95 scan.pdf",
        )
        if stdout:
            logger.info("stdout:\n%s", stdout)
        if stderr:
            logger.info("stderr:\n%s", stderr)
        logger.info(", ".join([f.name async for f in d.glob("*")]))
        logger.info("finished scan")
        await outfile.write_bytes(await (d / "scan.pdf").read_bytes())
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
    uvicorn.run(app, host="0.0.0.0", port=8000)  # ruff: ignore[hardcoded-bind-all-interfaces]
