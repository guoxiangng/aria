"""Module-level `graph` instance for the A2A server (see cli.py). Mirrors kagent's official
LangGraph BYO sample pattern (`from agent import graph`), adapted for kagent-langgraph's
checkpointer so investigation state can persist across turns in kagent's session store.

Eagerly loads MCP tools at import time (async, run via asyncio.run — happens once, before
uvicorn's event loop starts, so this is safe).
"""

from __future__ import annotations

import asyncio

import httpx
from kagent.core import KAgentConfig
from kagent.langgraph import KAgentCheckpointer

from investigation_agent.graph import build_graph, build_llm, load_tools

_llm = build_llm()
_tools = asyncio.run(load_tools())

_config = KAgentConfig()
_checkpointer = KAgentCheckpointer(
    client=httpx.AsyncClient(base_url=_config.url),
    app_name=_config.app_name,
)

graph = build_graph(_llm, _tools, checkpointer=_checkpointer)
