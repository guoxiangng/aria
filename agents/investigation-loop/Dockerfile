# Adapted from kagent's official LangGraph BYO sample Dockerfile, simplified for a standalone
# (non-monorepo) repo: https://github.com/kagent-dev/kagent/blob/main/python/samples/langgraph/currency/Dockerfile
FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY pyproject.toml README.md ./
COPY investigation_agent ./investigation_agent

RUN pip install --no-cache-dir .

ENV PYTHONPATH=/app
ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["python", "-m", "investigation_agent.cli"]
