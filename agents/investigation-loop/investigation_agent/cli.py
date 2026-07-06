"""A2A server entrypoint — what the Dockerfile CMD runs. This is the DEPLOYED path.

(For local experimentation without kagent's A2A/checkpointer machinery, use main.py instead.)

Pattern taken from kagent's official LangGraph BYO sample:
https://github.com/kagent-dev/kagent/blob/main/python/samples/langgraph/currency/currency/cli.py
"""

from __future__ import annotations

import json
import logging
import os

import uvicorn
from kagent.core import KAgentConfig
from kagent.langgraph import KAgentApp

from investigation_agent.agent import graph

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


def main() -> None:
    with open(os.path.join(os.path.dirname(__file__), "agent-card.json")) as f:
        agent_card = json.load(f)

    config = KAgentConfig()
    # tracing=False: this agent already gets OTel tracing via the same platform-level env vars
    # kagent injects into every agent pod (see infra/03-argocd) - avoid a second, LangSmith-specific
    # tracing path requiring its own API key. VERIFY after first deploy whether kagent's controller
    # injects those OTEL_* env vars into BYO deployments the same way it does Declarative ones.
    app = KAgentApp(graph=graph, agent_card=agent_card, config=config, tracing=False)

    port = int(os.getenv("PORT", "8080"))
    host = os.getenv("HOST", "0.0.0.0")
    logger.info(f"Starting investigation-loop A2A server on {host}:{port}")

    uvicorn.run(app.build(), host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()
