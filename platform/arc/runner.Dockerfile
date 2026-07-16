# Custom ARC runner image - Node.js + promptfoo pre-baked in.
#
# Why this exists: the plain ghcr.io/actions/actions-runner image has neither, so every
# eval CI run did a fresh `npm install promptfoo` from scratch (no cache, CPU-throttled
# pod) - measured hanging past 20 minutes on a tree with hundreds of transitive deps.
# Baking it into the image is a ONE-TIME build (rebuilt only when bumping the promptfoo
# version), not a per-run cost - doesn't reintroduce the per-CI-run fragility that the
# move away from Docker-per-job was meant to eliminate.
#
# Build + push (manual, infrequent - not part of any CI pipeline):
#   docker build -f platform/arc/runner.Dockerfile -t <ecr-repo>:latest platform/arc
#   docker push <ecr-repo>:latest
# Then reference the pushed tag in runner-values.yaml's template.spec.containers[].image.
FROM ghcr.io/actions/actions-runner:latest

USER root
# Debian's default `apt-get install nodejs` pulls Node 18, but promptfoo requires >=20.20 -
# confirmed the hard way (built fine with an EBADENGINE warning, failed at runtime with
# "promptfoo requires a supported Node.js runtime. Detected: v18.19.1"). Use NodeSource's
# setup script for a current major version instead of the distro package.
RUN apt-get update -qq \
    && apt-get install -y -qq curl \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y -qq nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g promptfoo@0.121.17
USER runner
