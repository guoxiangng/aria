"""The A2A application — a Strands-shaped equivalent of kagent.langgraph.KAgentApp.

There is no `kagent-strands` package, so this file is what you write instead. Note
how little of it is Strands-specific: exactly one line, the executor. Everything
else (`KAgentTaskStore`, `KAgentRequestContextBuilder`, `DefaultRequestHandler`,
`A2AStarletteApplication`, `configure_tracing`) comes from kagent-core and the a2a
SDK and is framework-neutral.

Structure mirrors kagent.langgraph._a2a.KAgentApp.build(), read from the installed
package in the live investigation-loop pod so this stays faithful to what kagent
actually does rather than to what its docs describe.
"""

from __future__ import annotations

import faulthandler
import logging
import tempfile

import httpx
from a2a.server.apps import A2AStarletteApplication
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.types import AgentCard
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
from kagent.core import KAgentConfig, configure_tracing
from kagent.core.a2a import (
    KAgentRequestContextBuilder,
    KAgentTaskStore,
    get_a2a_max_content_length,
)

from strands_investigator.executor import StrandsAgentExecutor

logger = logging.getLogger(__name__)


def health_check(request: Request) -> PlainTextResponse:
    return PlainTextResponse("OK")


def thread_dump(request: Request) -> PlainTextResponse:
    with tempfile.TemporaryFile(mode="w+") as tmp:
        faulthandler.dump_traceback(file=tmp, all_threads=True)
        tmp.seek(0)
        return PlainTextResponse(tmp.read())


class KAgentStrandsApp:
    """Builds the FastAPI app kagent's BYO contract expects.

    The contract is bigger than `spec.byo`'s description admits: A2A on :8080 AND
    a served `/.well-known/agent-card.json`, because that path is the readiness
    probe the controller configures. `A2AStarletteApplication.add_routes_to_app`
    is what serves it. See spec-byo-frameworks.md §3.
    """

    def __init__(self, *, agent_card: dict, config: KAgentConfig, tracing: bool = False) -> None:
        self.agent_card = AgentCard.model_validate(agent_card)
        self.config = config
        self._enable_tracing = tracing

    def build(self) -> FastAPI:
        http_client = httpx.AsyncClient(base_url=self.config.url)

        # The one framework-specific line in this file.
        agent_executor = StrandsAgentExecutor(app_name=self.config.app_name)

        task_store = KAgentTaskStore(http_client)
        request_context_builder = KAgentRequestContextBuilder(task_store=task_store)
        request_handler = DefaultRequestHandler(
            agent_executor=agent_executor,
            task_store=task_store,
            request_context_builder=request_context_builder,
        )

        a2a_app = A2AStarletteApplication(
            agent_card=self.agent_card,
            http_handler=request_handler,
            max_content_length=get_a2a_max_content_length(),
        )

        faulthandler.enable()

        app = FastAPI(
            title=f"KAgent Strands: {self.config.app_name}",
            description=f"Strands agent with KAgent integration: {self.agent_card.description}",
            version=self.agent_card.version,
        )

        # tracing=False by default: kagent's controller already injects the OTEL_*
        # env block into every agent pod (verified 2026-08-16 on the BYO deployment),
        # so a second tracing path would double-instrument.
        if self._enable_tracing:
            try:
                configure_tracing(self.config.name, self.config.namespace, app)
            except Exception:
                logger.exception("Failed to configure tracing")

        app.add_route("/health", methods=["GET"], route=health_check)
        app.add_route("/thread_dump", methods=["GET"], route=thread_dump)
        a2a_app.add_routes_to_app(app)
        return app
