ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH=amd64
ARG GLASS_BRANCH=dev

FROM node:22-bookworm-slim AS frontend
ARG GLASS_BRANCH
WORKDIR /src
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${GLASS_BRANCH}" https://github.com/pyMC-dev/pyMC-Glass.git .
WORKDIR /src/frontend
ENV VITE_API_BASE_URL=
RUN npm ci && npm run build

FROM python:3.12-slim

ARG BUILD_VERSION
ARG BUILD_ARCH
ARG GLASS_BRANCH

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        nginx \
        postgresql \
        postgresql-client \
        mosquitto \
        mosquitto-clients \
        procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/pymc-glass
RUN git clone --depth 1 --branch "${GLASS_BRANCH}" https://github.com/pyMC-dev/pyMC-Glass.git .
RUN pip install --upgrade pip \
    && pip install ./backend PyYAML

COPY --from=frontend /src/frontend/dist /usr/share/nginx/html
COPY --from=frontend /src/frontend/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 run.sh /run.sh
COPY pymc-glass.example.yaml /usr/share/pymc-glass/config.yaml.example

RUN rm -f /etc/nginx/sites-enabled/default \
    && sed -i 's#http://backend:8080#http://127.0.0.1:8080#g; s#listen 80;#listen 5173;#' /etc/nginx/conf.d/default.conf

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  org.opencontainers.image.title="Home Assistant Add-on: pyMC Glass Dev" \
  org.opencontainers.image.description="Home Assistant wrapper for pyMC Glass dev channel" \
  org.opencontainers.image.source="https://github.com/pyMC-dev/pyMC-Glass"

ENTRYPOINT ["/run.sh"]
