# SPDX-FileCopyrightText: 2026 bernikr <hi@berni.kr>
#
# SPDX-License-Identifier: MIT

FROM ghcr.io/astral-sh/uv:trixie-slim AS builder
SHELL ["sh", "-exc"]

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_PYTHON_INSTALL_DIR=/python \
    UV_PROJECT_ENVIRONMENT=/venv \
    UV_PREVIEW_FEATURES=frozen-lockfile

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-install-project

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.,target=/src,rw  \
    uv sync --locked --no-editable --directory /src

FROM debian:trixie-slim AS runtime
SHELL ["sh", "-exc"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,source=fix-pdf-permissions.sh,target=fix-pdf-permissions.sh \
    <<EOT
apt-get update -q
apt-get install -qqy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates sane-utils imagemagick wget

wget -O brscan4.deb https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
echo "027b73648722ac8c8eb1a9c419d284a6562cc763feac9740a2b75a683b092972  brscan4.deb" | sha256sum -c -
dpkg -i --force-all brscan4.deb
rm brscan4.deb

apt-get purge -qy wget && apt-get autoremove -qy

# Allow non-root users to configure and run the Brother scanner driver
mkdir -p /etc/opt/brother/scanner/brscan4
chmod -R a+rwX /etc/opt/brother /opt/brother

bash fix-pdf-permissions.sh

useradd -u 10001 -G scanner,lp appuser
EOT

COPY --from=builder /python /python
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

ARG VERSION
ENV VERSION=${VERSION:-"unspecified (docker)"}

USER appuser
EXPOSE 8000
HEALTHCHECK --start-period=30s CMD ["python", "-c", "import urllib.request; exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/hc').read() == b'OK' else 1)"]
CMD ["uvicorn", "app:app", "--host=0.0.0.0", "--port=8000", "--proxy-headers"]
