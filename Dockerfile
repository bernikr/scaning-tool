FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder
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

COPY . /src
WORKDIR /src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

FROM python:3.13-slim-bookworm
SHELL ["sh", "-exc"]

RUN <<EOF
apt-get update -qy
apt-get install -qy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    sane sane-utils wget imagemagick ca-certificates

wget https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
dpkg -i --force-all brscan4-0.4.11-1.amd64.deb
rm brscan4-0.4.11-1.amd64.deb

apt-get remove -qy wget
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

RUN --mount=type=bind,source=fix-pdf-permissions.sh,target=run.sh bash run.sh

COPY --from=builder --chown=app:app /app /app
ENV PATH="/app/bin:$PATH"

EXPOSE 8000
CMD ["uvicorn", "app:app", "--proxy-headers", "--port", "8000"]
