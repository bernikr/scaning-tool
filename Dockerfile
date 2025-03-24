FROM ghcr.io/astral-sh/uv:debian

WORKDIR /app

RUN apt update; apt install -y sane sane-utils
RUN wget https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
RUN dpkg -i --force-all brscan4-0.4.11-1.amd64.deb
RUN --mount=type=bind,source=fix-pdf-permissions.sh,target=run.sh ./run.sh

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Install the project's dependencies using the lockfile and settings
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.python-version,target=.python-version \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# Then, add the rest of the project source code and install it
# Installing separately from its dependencies allows optimal layer caching
ADD app.py pyproject.toml uv.lock .python-version /app/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# Reset the entrypoint, don't invoke `uv`
ENTRYPOINT []

CMD ["fastapi", "run", "app.py", "--proxy-headers", "--port", "8000"]
