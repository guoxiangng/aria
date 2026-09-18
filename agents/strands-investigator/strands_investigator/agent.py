"""The Strands agent itself.

Deliberate contrast with `investigation-loop` (the LangGraph BYO agent in this repo):

    investigation-loop   you build the loop. A StateGraph with explicit nodes
                         (gather -> hypothesize -> verify -> conclude) and a
                         `should_continue` function YOU can unit-test.

    strands-investigator you do NOT build the loop. Strands runs a model-driven
                         event loop; the branch decision lives with the model,
                         shaped only by the system prompt and the tools on offer.

Same task, same MCP tool server, same cluster. The loop's owner is the variable
under test. See aria/docs/spec-byo-frameworks.md §2.
"""

from __future__ import annotations

import logging
import os

from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp.mcp_client import MCPClient

logger = logging.getLogger(__name__)

# kagent's built-in MCP tool server — the SAME endpoint investigation-loop uses,
# so the two agents are offered an identical capability surface.
MCP_SERVER_URL = os.getenv("MCP_SERVER_URL", "http://kagent-tools.kagent:8084/mcp")

# Strands defaults to Amazon Bedrock + Claude. We pin the model explicitly rather
# than relying on that default, so the article can state exactly what ran.
# Matches the cluster's existing `bedrock-sonnet` ModelConfig.
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "global.anthropic.claude-sonnet-4-6")
AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-1")

# Read-only tools only — the same constraint investigation-loop operates under.
# kagent-tools exposes mutating tools too (k8s_patch_resource etc.); naming the
# allowed set here is a configuration constraint, not a network boundary.
READ_ONLY_TOOLS = [
    "k8s_get_resources",
    "k8s_get_events",
    "k8s_get_pod_logs",
    "k8s_describe_resource",
    "k8s_get_available_api_resources",
]

SYSTEM_PROMPT = """\
You are ARIA's Strands-based Kubernetes investigator.

Your job: find the ROOT CAUSE of the issue described by the user, using only the
read-only tools available to you.

Method — you decide when to stop, but work this way:
  1. Gather concrete evidence with tools. Never assert anything you have not observed.
  2. Form an explicit hypothesis.
  3. Try to VERIFY or FALSIFY it with another tool call.
  4. If it does not hold, revise and gather again. If it holds, conclude.

Rules:
- You run in the `kagent` namespace of an EKS cluster named `aria`. If a namespace
  is not stated, ask or check rather than assuming one from your own name.
- Quote the evidence (resource names, event messages, log lines) that supports your
  conclusion. An unevidenced conclusion is a failure, not an answer.
- If the evidence is insufficient, say so plainly. Do not invent findings.
- Keep tool calls purposeful; you have a bounded budget, not an unlimited one.

Finish with:
  EVIDENCE:   the observations you actually made
  ROOT CAUSE: your conclusion, or an explicit statement that it is undetermined
  CONFIDENCE: high | medium | low
"""


def build_mcp_client() -> MCPClient:
    """MCP client over streamable-HTTP to kagent-tools.

    `url=` makes Strands construct the transport itself. The older
    `MCPClient(lambda: streamablehttp_client(url))` form in most tutorials breaks on
    mcp 2.x, which renamed that function (verified in-image 2026-09-14).
    """
    return MCPClient(url=MCP_SERVER_URL, application_name="strands-investigator")


def build_model() -> BedrockModel:
    """Bedrock model. Credentials come from EKS Pod Identity — no static keys.

    Strands would default to Bedrock anyway; pinning it makes the deployed model
    explicit and greppable.
    """
    return BedrockModel(model_id=BEDROCK_MODEL_ID, region_name=AWS_REGION)


def build_agent(tools: list) -> Agent:
    """Assemble the agent. Note what is NOT here: no graph, no edges, no
    termination function. That is the entire point of this implementation."""
    return Agent(model=build_model(), tools=tools, system_prompt=SYSTEM_PROMPT)


def filter_read_only(tools: list) -> list:
    """Keep only the read-only subset, matching investigation-loop's constraint.

    If a name in READ_ONLY_TOOLS is absent from the server, it is skipped rather
    than raising — the tool server's inventory moves between kagent versions.
    """
    selected = [t for t in tools if getattr(t, "tool_name", None) in READ_ONLY_TOOLS]
    if not selected:
        logger.warning(
            "No READ_ONLY_TOOLS matched the %d tools advertised by %s — "
            "falling back to the full advertised set. Check tool names.",
            len(tools),
            MCP_SERVER_URL,
        )
        return tools
    logger.info("Using %d read-only tools of %d advertised", len(selected), len(tools))
    return selected
