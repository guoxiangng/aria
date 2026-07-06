"""Local CLI runner for investigation-loop — for experimenting BEFORE containerizing/deploying.

Usage:
    uv run python -m investigation_agent.main "pod X in namespace kagent keeps restarting"

Requires:
    - .env filled in (see .env.example) with Azure OpenAI creds
    - kagent-tools MCP server reachable — either in-cluster, or locally via:
        kubectl -n kagent port-forward svc/kagent-tools 8084:8084
      and MCP_SERVER_URL=http://localhost:8084/mcp in .env
"""

from __future__ import annotations

import asyncio
import sys

from dotenv import load_dotenv

from investigation_agent.graph import DEFAULT_MAX_ITERATIONS, build_graph, build_llm, load_tools


async def run(target: str, max_iterations: int = DEFAULT_MAX_ITERATIONS) -> None:
    load_dotenv()
    tools = await load_tools()
    llm = build_llm()
    app = build_graph(llm, tools)

    result = await app.ainvoke(
        {
            "target": target,
            "evidence": [],
            "hypothesis": "",
            "confidence": 0.0,
            "iteration": 0,
            "max_iterations": max_iterations,
            "conclusion": "",
        }
    )

    print("\n=== EVIDENCE TRAIL ===")
    for e in result["evidence"]:
        print(f"- {e}")
    print(f"\n=== FINAL HYPOTHESIS (confidence {result['confidence']:.2f}, "
          f"{result['iteration']} verify round(s)) ===")
    print(result["hypothesis"])
    print("\n=== CONCLUSION ===")
    print(result["conclusion"])


if __name__ == "__main__":
    target_arg = " ".join(sys.argv[1:]) or "a pod keeps restarting intermittently in namespace kagent"
    asyncio.run(run(target_arg))
