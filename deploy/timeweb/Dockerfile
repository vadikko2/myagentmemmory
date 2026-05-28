ARG III_VERSION=0.11.2

FROM iiidev/iii:${III_VERSION} AS iii-image

FROM node:22-slim

ARG AGENTMEMORY_VERSION=0.9.12
ARG III_VERSION=0.11.2
ARG III_SDK_VERSION=0.11.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    tini \
    gosu \
    curl \
    tar \
    gzip \
    awscli \
    cron \
    nginx \
    socat \
 && rm -rf /var/lib/apt/lists/*

COPY --from=iii-image /app/iii /usr/local/bin/iii

WORKDIR /opt/agentmemory
RUN printf '{"name":"agentmemory-deploy","version":"1.0.0","private":true,"overrides":{"iii-sdk":"%s"}}\n' "${III_SDK_VERSION}" > package.json \
 && npm install "@agentmemory/agentmemory@${AGENTMEMORY_VERSION}" --omit=optional --no-fund --no-audit \
 && ln -s /opt/agentmemory/node_modules/.bin/agentmemory /usr/local/bin/agentmemory

ENV AGENTMEMORY_III_VERSION=${III_VERSION} \
    TINI_SUBREAPER=1 \
    ENABLE_NGINX_PROXY=true \
    PROXY_PORT=80 \
    III_REST_PORT=8080 \
    III_STREAMS_PORT=8081 \
    ENABLE_PORT_COMPAT=true

COPY nginx.conf /etc/agentmemory/nginx.conf
COPY --chmod=0755 entrypoint.sh /usr/local/bin/agentmemory-entrypoint.sh
COPY --chmod=0755 backup.sh /usr/local/bin/backup.sh

RUN touch /var/log/backup.log && chmod 666 /var/log/backup.log \
 && mkdir -p /tmp/nginx-client-body /tmp/nginx-proxy

EXPOSE 80 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agentmemory-entrypoint.sh"]
