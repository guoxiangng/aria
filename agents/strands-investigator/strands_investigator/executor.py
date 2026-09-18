"""StrandsAgentExecutor — the ONLY kagent-specific code in this agent.

This is the finding from aria/docs/spec-byo-frameworks.md §3 made concrete:
`kagent-langgraph` is LangGraph-specific, but it sits on `kagent-core`, which is
framework-clean. So bringing a new framework to kagent does NOT mean writing an
A2A server. It means writing one `AgentExecutor` — this file — and reusing
kagent-core's task store, request-context builder and tracing.

Modelled on kagent.langgraph._executor.LangGraphAgentExecutor, read from the
installed package inside the running investigation-loop pod (kagent 0.9.11).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime

from a2a.server.agent_execution import AgentExecutor
from a2a.server.agent_execution.context import RequestContext
from a2a.server.events.event_queue import EventQueue
from a2a.types import (
    Artifact,
    Part,
    TaskArtifactUpdateEvent,
    TaskState,
    TaskStatus,
    TaskStatusUpdateEvent,
    TextPart,
)

from strands_investigator.agent import build_agent, build_mcp_client, filter_read_only

logger = logging.getLogger(__name__)


class StrandsAgentExecutor(AgentExecutor):
    """Drives a Strands agent for one A2A task and publishes protocol events."""

    def __init__(self, app_name: str) -> None:
        self.app_name = app_name

    # ------------------------------------------------------------------ helpers

    def _now(self) -> str:
        return datetime.now(UTC).isoformat()

    async def _status(
        self,
        event_queue: EventQueue,
        context: RequestContext,
        state: TaskState,
        *,
        final: bool = False,
        message=None,
    ) -> None:
        await event_queue.enqueue_event(
            TaskStatusUpdateEvent(
                task_id=context.task_id,
                context_id=context.context_id,
                status=TaskStatus(state=state, timestamp=self._now(), message=message),
                final=final,
                metadata={"app_name": self.app_name},
            )
        )

    def _run_strands_sync(self, prompt: str) -> str:
        """Run the Strands agent to completion.

        Strands' `Agent.__call__` is synchronous, so the caller runs this in a
        worker thread to avoid blocking the event loop. The MCP session is opened
        per request: sessions are not guaranteed to survive an idle agent pod, and
        correctness beats shaving a connection setup here.
        """
        mcp_client = build_mcp_client()
        with mcp_client:
            tools = filter_read_only(mcp_client.list_tools_sync())
            agent = build_agent(tools)
            result = agent(prompt)
            return str(result)

    # ------------------------------------------------------------------- a2a API

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        if not context.message:
            raise ValueError("A2A request must have a message")

        prompt = context.get_user_input()
        if not prompt:
            raise ValueError("A2A message carried no text part to act on")

        # New task -> announce submitted. Resumed tasks already have one.
        if not context.current_task:
            await self._status(
                event_queue, context, TaskState.submitted, message=context.message
            )

        await self._status(event_queue, context, TaskState.working)

        try:
            # Strands owns the loop from here. There is no branch decision of ours
            # to make, and nothing of ours to unit-test - which is the comparison.
            answer = await asyncio.to_thread(self._run_strands_sync, prompt)
        except Exception:
            logger.exception("Strands agent execution failed")
            await self._status(event_queue, context, TaskState.failed, final=True)
            return

        await event_queue.enqueue_event(
            TaskArtifactUpdateEvent(
                task_id=context.task_id,
                context_id=context.context_id,
                artifact=Artifact(
                    artifact_id="investigation-result",
                    name="investigation-result",
                    parts=[Part(root=TextPart(text=answer))],
                ),
                last_chunk=True,
            )
        )
        await self._status(event_queue, context, TaskState.completed, final=True)

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        """Strands exposes no mid-flight cancellation hook we can call, so this
        reports the state truthfully rather than pretending to interrupt the loop.
        Another honest cost of not owning the loop."""
        logger.info("Cancel requested for task %s — not supported by this executor", context.task_id)
        await self._status(event_queue, context, TaskState.canceled, final=True)
