FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS env-builder
SHELL ["sh", "-exc"]

ENV UV_COMPILE_BYTECODE=1 \ 
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/app

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.python-version,target=.python-version \
    uv venv /app

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev

FROM env-builder AS app-builder

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.,target=/src,rw  \
    uv sync --locked --no-dev --no-editable --directory /src

FROM python:3.13-slim-bookworm
SHELL ["sh", "-exc"]

ADD --checksum=sha256:027b73648722ac8c8eb1a9c419d284a6562cc763feac9740a2b75a683b092972 \
    https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb ./brscan4.deb

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<EOT
apt-get update -q
apt-get install -qqy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    sane sane-utils imagemagick wget

dpkg -i --force-all brscan4.deb
rm brscan4.deb
EOT

RUN --mount=type=bind,source=fix-pdf-permissions.sh,target=run.sh bash run.sh

COPY --from=env-builder --chown=app:app /app /app
COPY --from=app-builder --chown=app:app /app /app
ENV PATH="/app/bin:$PATH"

ARG VERSION
ENV VERSION=${VERSION:-"unspecified (docker)"}
EXPOSE 8000
HEALTHCHECK --start-period=30s CMD [ "$( wget -qO - http://127.0.0.1:8000/hc )" = OK ]
CMD ["uvicorn", "app:app", "--host=0.0.0.0", "--port=8000", "--proxy-headers"]
