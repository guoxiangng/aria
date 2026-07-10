# Eval runner - packages promptfoo + our configs/transforms so eval can run as a
# Kubernetes Job inside the cluster (real in-cluster Service DNS, no port-forward,
# no tunnel needed from CI). See run-all.sh for how the configs are pointed at
# real Services instead of the localhost port-forwards used for local dev runs.
FROM node:22-slim

WORKDIR /app

RUN npm install --no-save promptfoo@0.121.17

COPY *.promptfooconfig.yaml ./
COPY transforms ./transforms
COPY run-all.sh ./

RUN chmod +x run-all.sh

ENTRYPOINT ["./run-all.sh"]
