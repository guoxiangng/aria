"""ARIA's investigation-loop agent: a hand-built LangGraph StateGraph.

Demonstrates what a flat ReAct loop doesn't give you cleanly: an explicit, bounded CYCLE —
gather evidence -> hypothesize -> verify -> (loop back if unconfirmed) -> conclude.

Reuses kagent's EXISTING MCP tool server (kagent-tools) rather than reimplementing tools,
scoped to the SAME read-only allowlist as the `cluster-diagnostics` Agent CR (consistent
security posture: this BYO agent is also diagnostic-only, no mutating tools).

State includes `messages` so this graph is compatible with kagent's A2A executor (see
kagent-langgraph's _executor.py — it invokes graphs with {"messages": [("user", text)]}
and reads streamed messages back). `main.py` (local CLI testing) and `agent.py`/`cli.py`
(the real A2A server) both use the SAME graph.
"""

from __future__ import annotations

import operator
import os
import re
from typing import Annotated, TypedDict

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_openai import AzureChatOpenAI
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages

# Same allowlist as agents/cluster-diagnostics/agent.yaml — read-only, no mutating tools.
READ_ONLY_TOOLS = {
    "k8s_get_resources",
    "k8s_describe_resource",
    "k8s_get_events",
    "k8s_get_pod_logs",
    "k8s_get_resource_yaml",
    "k8s_get_available_api_resources",
    "k8s_get_cluster_configuration",
    "k8s_check_service_connectivity",
}

CONFIDENCE_THRESHOLD = 0.75
DEFAULT_MAX_ITERATIONS = 3


class InvestigationState(TypedDict):
    # Required for kagent A2A compatibility — the executor invokes with {"messages": [("user", text)]}
    # and reads the final AIMessage back out. NOT present in a plain `main.py` local invocation.
    messages: Annotated[list[BaseMessage], add_messages]
    # Everything below is absent on the very FIRST call via the A2A path — every node must
    # use .get() with a default, never direct indexing.
    target: str
    evidence: Annotated[list[str], operator.add]
    hypothesis: str
    confidence: float
    iteration: int
    max_iterations: int
    conclusion: str


def build_llm() -> AzureChatOpenAI:
    """Same Azure deployment as the rest of ARIA (matches the team's LADP .env naming)."""
    return AzureChatOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        azure_deployment=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT_NAME"],
        api_version=os.environ.get("AZURE_OPENAI_API_VERSION", "2024-12-01-preview"),
        api_key=os.environ["AZURE_OPENAI_API_KEY"],
        temperature=0,
    )


async def load_tools():
    """Load tools from kagent's existing MCP server, scoped to READ_ONLY_TOOLS.

    In-cluster default DNS: http://kagent-tools.kagent:8084/mcp
    For local dev: `kubectl -n kagent port-forward svc/kagent-tools 8084:8084` and set
    MCP_SERVER_URL=http://localhost:8084/mcp (see .env.example).
    """
    mcp_url = os.environ.get("MCP_SERVER_URL", "http://kagent-tools.kagent:8084/mcp")
    client = MultiServerMCPClient({"kagent-tools": {"transport": "http", "url": mcp_url}})
    all_tools = await client.get_tools()
    return [t for t in all_tools if t.name in READ_ONLY_TOOLS]


def _parse_hypothesis(text: str) -> tuple[str, float]:
    hyp_match = re.search(r"HYPOTHESIS:\s*(.+?)(?:\n|$)", text, re.IGNORECASE)
    conf_match = re.search(r"CONFIDENCE:\s*([0-9.]+)", text, re.IGNORECASE)
    hypothesis = hyp_match.group(1).strip() if hyp_match else text.strip()
    try:
        confidence = float(conf_match.group(1)) if conf_match else 0.3
    except ValueError:
        confidence = 0.3
    return hypothesis, max(0.0, min(1.0, confidence))


def _resolve_target(state: InvestigationState) -> str:
    """Local CLI (main.py) sets `target` directly. The A2A path only provides `messages` —
    derive the target from the latest human message instead."""
    if state.get("target"):
        return state["target"]
    messages = state.get("messages") or []
    for msg in reversed(messages):
        content = getattr(msg, "content", None)
        if content and getattr(msg, "type", None) in (None, "human"):
            return content
    return "(no target provided)"


def build_graph(llm: AzureChatOpenAI, tools: list, checkpointer=None):
    tools_by_name = {t.name: t for t in tools}
    llm_with_tools = llm.bind_tools(tools)

    async def gather_evidence(state: InvestigationState) -> dict:
        target = _resolve_target(state)
        evidence = state.get("evidence") or []
        context = "\n".join(evidence) or "(none yet)"
        prompt = [
            SystemMessage(
                content="You investigate Kubernetes issues using read-only tools only. "
                "Call exactly ONE tool that gathers the next most useful piece of evidence."
            ),
            HumanMessage(
                content=f"Target: {target}\nEvidence so far:\n{context}\n\n"
                f"Current hypothesis (if any): {state.get('hypothesis') or '(none yet)'}"
            ),
        ]
        response = await llm_with_tools.ainvoke(prompt)
        new_evidence = []
        for call in getattr(response, "tool_calls", []) or []:
            tool = tools_by_name[call["name"]]
            result = await tool.ainvoke(call["args"])
            new_evidence.append(f"[{call['name']}({call['args']})] -> {result}")
        if not new_evidence:
            new_evidence = [f"(no tool called) {response.content}"]
        # Reset counters only on a genuinely fresh investigation (target not yet set in state).
        fresh = {"target": target} if not state.get("target") else {}
        if fresh:
            fresh.update({"evidence": [], "hypothesis": "", "confidence": 0.0, "iteration": 0})
        return {**fresh, "evidence": new_evidence}

    async def hypothesize(state: InvestigationState) -> dict:
        target = _resolve_target(state)
        context = "\n".join(state.get("evidence") or [])
        prompt = [
            SystemMessage(
                content="Given the evidence, propose ONE root-cause hypothesis and a confidence "
                "score. Respond EXACTLY as:\nHYPOTHESIS: <text>\nCONFIDENCE: <0.0-1.0>"
            ),
            HumanMessage(content=f"Target: {target}\nEvidence:\n{context}"),
        ]
        response = await llm.ainvoke(prompt)
        hypothesis, confidence = _parse_hypothesis(response.content)
        return {"hypothesis": hypothesis, "confidence": confidence}

    async def verify_hypothesis(state: InvestigationState) -> dict:
        target = _resolve_target(state)
        evidence = state.get("evidence") or []
        prompt = [
            SystemMessage(
                content="Call exactly ONE tool that would specifically CONFIRM or DENY the given "
                "hypothesis - not a generic evidence-gathering call."
            ),
            HumanMessage(
                content=f"Target: {target}\nHypothesis to verify: {state.get('hypothesis')}\n"
                f"Evidence so far:\n" + "\n".join(evidence)
            ),
        ]
        response = await llm_with_tools.ainvoke(prompt)
        new_evidence = []
        for call in getattr(response, "tool_calls", []) or []:
            tool = tools_by_name[call["name"]]
            result = await tool.ainvoke(call["args"])
            new_evidence.append(f"[verify:{call['name']}({call['args']})] -> {result}")

        rescore_prompt = [
            SystemMessage(
                content="Given the ORIGINAL hypothesis and ALL evidence (including new evidence "
                "just gathered to verify it), re-score confidence. Respond EXACTLY as:\n"
                "CONFIDENCE: <0.0-1.0>"
            ),
            HumanMessage(
                content=f"Hypothesis: {state.get('hypothesis')}\nAll evidence:\n"
                + "\n".join(evidence + new_evidence)
            ),
        ]
        rescore_response = await llm.ainvoke(rescore_prompt)
        _, confidence = _parse_hypothesis(rescore_response.content)

        return {
            "evidence": new_evidence,
            "confidence": confidence,
            "iteration": (state.get("iteration") or 0) + 1,
        }

    def should_continue(state: InvestigationState) -> str:
        if (state.get("confidence") or 0.0) >= CONFIDENCE_THRESHOLD:
            return "conclude"
        max_iter = state.get("max_iterations") or DEFAULT_MAX_ITERATIONS
        if (state.get("iteration") or 0) >= max_iter:
            return "conclude"  # bounded loop — "loop engineering": never spin forever
        return "gather_evidence"

    async def conclude(state: InvestigationState) -> dict:
        target = _resolve_target(state)
        evidence = state.get("evidence") or []
        confidence = state.get("confidence") or 0.0
        prompt = [
            SystemMessage(
                content="Write a concise final root-cause summary for a human SRE, citing the "
                "specific evidence that supports it. If confidence is low, say so explicitly and "
                "state what's still uncertain rather than overstating confidence."
            ),
            HumanMessage(
                content=f"Target: {target}\n"
                f"Final hypothesis: {state.get('hypothesis')} (confidence {confidence:.2f})\n"
                f"All evidence:\n" + "\n".join(evidence)
            ),
        ]
        response = await llm.ainvoke(prompt)
        # Appended to `messages` — this is what kagent's A2A executor streams back as the reply.
        return {"conclusion": response.content, "messages": [AIMessage(content=response.content)]}

    graph = StateGraph(InvestigationState)
    graph.add_node("gather_evidence", gather_evidence)
    graph.add_node("hypothesize", hypothesize)
    graph.add_node("verify_hypothesis", verify_hypothesis)
    graph.add_node("conclude", conclude)

    graph.set_entry_point("gather_evidence")
    graph.add_edge("gather_evidence", "hypothesize")
    graph.add_edge("hypothesize", "verify_hypothesis")
    graph.add_conditional_edges(
        "verify_hypothesis",
        should_continue,
        {"conclude": "conclude", "gather_evidence": "gather_evidence"},
    )
    graph.add_edge("conclude", END)

    return graph.compile(checkpointer=checkpointer)
