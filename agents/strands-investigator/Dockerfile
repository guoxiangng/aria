# Mirrors agents/investigation-loop/Dockerfile so the two BYO images differ only
# in their framework - keeping the "lines of glue / image size" comparison honest.
FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY pyproject.toml README.md ./
COPY strands_investigator ./strands_investigator

RUN pip install --no-cache-dir .

ENV PYTHONPATH=/app
ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["python", "-m", "strands_investigator.cli"]
