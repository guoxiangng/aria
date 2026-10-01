// Extracts both the agent's final answer AND the raw tool-call evidence it was
// based on, from a kagent A2A message/send response. Feeding both to the judge
// (not just the final text) lets the rubric catch confidently-wrong answers
// whose "evidence" doesn't actually support the claim - the whole point of
// this eval loop, not just "did it answer in a plausible-sounding way."
module.exports = (json) => {
  const history = json?.result?.history || [];

  // A single agent turn can bundle multiple tool calls as separate `parts`
  // within one message (not separate messages) - must walk every part, not
  // just parts[0], or multi-tool-call turns silently lose evidence.
  const agentParts = history.filter((m) => m.role === 'agent').flatMap((m) => m.parts || []);

  // Args live on the function_call part; results on the matching
  // function_response part (joined by call id). Surface both - a claim like
  // "checked the kagent namespace" can only be verified against the actual
  // args passed, not just the result text.
  const callArgsById = new Map(
    agentParts
      .filter((p) => p.metadata?.kagent_type === 'function_call')
      .map((p) => [p.data?.id, p.data?.args])
  );

  // MCP tool responses look like {content: [{type, text}]}. Sub-agent
  // delegation (orchestrators calling other Agents via A2A) responds as
  // {result: "..."} instead - same call/response shape, different payload.
  // Handle both so this transform works for Declarative, orchestrator, and
  // BYO agents alike.
  const extractResponseText = (response) => {
    if (response?.content) return response.content.map((c) => c.text).join('\n');
    if (typeof response?.result === 'string') return response.result;
    return JSON.stringify(response);
  };

  const toolEvidence = agentParts
    .filter((p) => p.metadata?.kagent_type === 'function_response')
    .map((p) => {
      const part = p.data;
      const name = part?.name || 'unknown_tool';
      const args = callArgsById.get(part?.id);
      const text = extractResponseText(part?.response);
      return `--- tool: ${name}(${JSON.stringify(args)}) ---\n${text}`;
    })
    .join('\n\n');

  const finalAnswer =
    json?.result?.artifacts?.[0]?.parts?.[0]?.text ||
    json?.result?.status?.message?.parts?.[0]?.text ||
    '(no final answer found)';

  // A task in `input-required` has not finished, and its missing final answer is
  // NOT the agent declining. kagent gates delegation to a remote agent behind an
  // ADK long-running confirmation BY DEFAULT - no `requireApproval` in the spec is
  // needed - so an orchestrator sent a single message/send stops and waits for a
  // `function_response` this harness never sends. Left unlabelled it renders as
  // '(no final answer found)', which reads exactly like silence; that misreading
  // was recorded as an agent defect twice before the cause was found.
  const state = json?.result?.status?.state;
  const pausedFor = (json?.result?.status?.message?.parts || [])
    .filter((p) => p?.kind === 'data' && p?.metadata?.kagent_is_long_running)
    .map((p) => p?.data?.args?.originalFunctionCall?.name || p?.data?.name)
    .filter(Boolean)
    .join(', ');

  if (state === 'input-required') {
    return [
      'HARNESS LIMITATION - NOT A BEHAVIOURAL RESULT.',
      `The task is still in state "${state}": it paused for approval` +
        (pausedFor ? ` before calling ${pausedFor}` : '') +
        ', and this harness cannot answer an approval, so the agent never reached',
      'a final answer. Grade this as broken tooling - not as the agent refusing,',
      'hallucinating, or staying silent.',
      '',
      'TOOL EVIDENCE gathered before the pause:',
      toolEvidence || '(no tool calls completed)',
    ].join('\n');
  }

  return [
    `TASK STATE: ${state || '(unknown)'}`,
    'TOOL EVIDENCE (raw, ground truth - trust this over the final answer):',
    toolEvidence || '(no tool calls were made)',
    '',
    'FINAL ANSWER (what the agent told the user):',
    finalAnswer,
  ].join('\n');
};
