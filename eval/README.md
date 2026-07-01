# eval/ — shared evaluation framework

Generic engine (build once); the per-agent golden sets live in each `agents/<name>/content-pack/`.

- `runner/` — runs an agent over its golden set, captures answer + tool-call trajectory, scores via
  LLM-as-judge (groundedness, correctness, tool-use, safety), and gates the pipeline on regression.

Engine options to wrap (don't rebuild): promptfoo / DeepEval / Bedrock Evaluations. Red-team: promptfoo / garak / PyRIT.
