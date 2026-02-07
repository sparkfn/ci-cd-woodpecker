# =============================================================================
# Webhook Handler Container
# =============================================================================
# Lightweight image for running the webhook-handler.sh script.
# Scripts and config are bind-mounted at runtime (no COPY needed).
#
# Build:   docker compose build webhook-handler
# Run:     docker compose up -d webhook-handler
# =============================================================================

FROM python:3.12-alpine

RUN apk add --no-cache bash curl openssl jq

WORKDIR /app

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD curl -f http://localhost:9000/health || exit 1

ENTRYPOINT ["/app/scripts/webhook-handler.sh", "--serve"]
