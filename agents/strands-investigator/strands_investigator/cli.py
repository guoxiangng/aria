"""A2A server entrypoint — what the Dockerfile CMD runs. This is the DEPLOYED path.

Mirrors investigation-loop/investigation_agent/cli.py so the two BYO agents differ
only where the comparison intends them to.
"""

from __future__ import annotations

import json
import logging
import os

import uvicorn
from kagent.core import KAgentConfig

from strands_investigator.app import KAgentStrandsApp

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


def main() -> None:
    with open(os.path.join(os.path.dirname(__file__), "agent-card.json")) as f:
        agent_card = json.load(f)

    config = KAgentConfig()
    app = KAgentStrandsApp(agent_card=agent_card, config=config, tracing=False)

    port = int(os.getenv("PORT", "8080"))
    host = os.getenv("HOST", "0.0.0.0")
    logger.info("Starting strands-investigator A2A server on %s:%s", host, port)

    uvicorn.run(app.build(), host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()
