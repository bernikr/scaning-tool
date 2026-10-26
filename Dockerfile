# SPDX-FileCopyrightText: 2026 bernikr <hi@berni.kr>
#
# SPDX-License-Identifier: MIT

FROM ghcr.io/astral-sh/uv:bookworm-slim AS builder
SHELL ["sh", "-exc"]

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_PYTHON_INSTALL_DIR=/python \
    UV_PROJECT_ENVIRONMENT=/venv

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.,target=/src,rw  \
    uv sync --locked --no-dev --no-editable --directory /src

FROM debian:bookworm-slim
SHELL ["sh", "-exc"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,source=fix-pdf-permissions.sh,target=fix-pdf-permissions.sh \
    <<EOT
apt-get update -q
apt-get install -qqy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates sane sane-utils imagemagick wget

wget -O brscan4.deb https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
echo "027b73648722ac8c8eb1a9c419d284a6562cc763feac9740a2b75a683b092972  brscan4.deb" | sha256sum -c -
dpkg -i --force-all brscan4.deb
rm brscan4.deb

bash fix-pdf-permissions.sh
EOT

#TODO: run as nonroot

COPY --from=builder /python /python
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

ARG VERSION
ENV VERSION=${VERSION:-"unspecified (docker)"}
EXPOSE 8000
HEALTHCHECK --start-period=30s CMD test "$(wget -qO- -T 3 http://127.0.0.1:8000/hc)" = "OK"
CMD ["uvicorn", "app:app", "--host=0.0.0.0", "--port=8000", "--proxy-headers"]
