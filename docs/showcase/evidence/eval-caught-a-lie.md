# Evidence — the eval loop caught a confident false answer

- **Captured:** 2026-07-28, first real run of the groundedness rubric
- **Source:** `eval/` (promptfoo + the trajectory transform)
- **Establishes:** grading an answer's *shape* cannot catch a lie told in the right shape. Grading the
  *evidence* can.

## What the naive rubric passed

The first rubric graded the final answer text — roughly *"does this cite specific evidence and give a
clear conclusion?"* It passed this:

```
Q: Is the `kagent` namespace under resource pressure? Report actual usage against limits.

A (scored PASS): I don't see a `kagent` namespace... `No resources found in kagent namespace.`
```

The namespace had been running for weeks with **fifteen pods** in it. The answer is not slightly off, it
is categorically false — and it passed, because it *did* cite evidence and *did* reach a clear
conclusion. Structure is exactly what a confident hallucination provides.

## The fix

The agent hadn't hallucinated silently. It made real tool calls, got real results, and *then* its summary
contradicted what its own tools had returned. The lie lived in the gap between evidence and summary.

So the rubric stopped judging the summary. kagent returns the full trajectory in `result.history[]`,
tagged by `metadata.kagent_type` (`function_call` / `function_response`). A transform pulls the tool
arguments **and** the tool results out of that history and hands them to the judge next to the final
answer:

> *Here is the raw tool evidence, and here is what the agent told the user. FAIL if any claim in the
> answer isn't supported by — or contradicts — the evidence.*

The namespace lie now fails instantly: the evidence shows fifteen pods, the answer claims zero, and the
judge sees a contradiction it structurally could not see before.

## The second finding, which is the better one

The first two versions of that transform were buggy — and buggy in the most dangerous way available:
they made the eval *look* like it was working while it quietly saw nothing. The metadata was read at the
wrong nesting level, so the transform found "no tool calls" on every run and the groundedness check
passed everything.

**A silent-failure detector that fails silently.** The harness needs the same scrutiny as the thing it
grades — the same lesson the identity deny-test taught independently.

## Honest limits

- One rubric, one agent family, a handful of cases. This is a working gate, not a benchmark.
- The judge is itself a model. It catches contradictions between evidence and summary; it does not
  establish that the evidence was the *right* evidence to gather.
