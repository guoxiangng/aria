// Rough proxy for "did investigation-loop actually run its stateful graph, not just
// answer in one shot": count LangGraph checkpoint-write traces in Langfuse within a
// window around this test. A single full pass (gather->hypothesize->verify->conclude)
// checkpoints ~6 times (measured empirically); a trivial/broken response wouldn't.
// This does NOT prove it looped multiple times specifically - just that real multi-step
// graph execution happened. See eval/README.md for the fuller discussion.
const MIN_CHECKPOINTS = 4;
const WINDOW_MS = 120_000; // generous - covers slow LLM calls + Langfuse ingestion lag
const INGEST_DELAY_MS = 5_000; // Langfuse's read API lags slightly behind ingestion

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

module.exports = async (output, context) => {
  const auth = process.env.LANGFUSE_AUTH; // base64("public:secret"), same as OTEL_EXPORTER_OTLP_HEADERS
  if (!auth) {
    return { pass: false, score: 0, reason: 'LANGFUSE_AUTH not set - cannot verify graph execution' };
  }

  await sleep(INGEST_DELAY_MS);

  const now = new Date();
  const from = new Date(now.getTime() - WINDOW_MS).toISOString();

  const res = await fetch(
    `https://us.cloud.langfuse.com/api/public/traces?limit=50&fromTimestamp=${from}`,
    { headers: { Authorization: `Basic ${auth}` } }
  );
  const data = await res.json();
  const checkpointCount = (data.data || []).filter(
    (t) => t.name === 'POST /api/langgraph/checkpoints'
  ).length;

  const pass = checkpointCount >= MIN_CHECKPOINTS;
  return {
    pass,
    score: pass ? 1 : 0,
    reason: `${checkpointCount} checkpoint writes in the last ${WINDOW_MS / 1000}s (need >= ${MIN_CHECKPOINTS}) - ${pass ? 'real multi-step graph execution confirmed' : 'looks like a single-shot response, not the stateful graph'}`,
  };
};
