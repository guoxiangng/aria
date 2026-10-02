# Spec — bringing the group project's RAG service into ARIA

> **Status:** not built. Architecture decision first; no code until the §4 governance question has an
> answer, because that answer changes the shape rather than the schedule.
> **Written:** 2026-10-03.
> **Origin:** a parallel group project (NCS LADP programme) built a working document-retrieval
> assistant. It runs entirely on one laptop. The question here is what a platform-shaped version
> looks like, and what must *not* come across.
> **Supersedes:** `spec-corpus-mcp.md` §2's "FastAPI backend — **Drop**" line. That decision assumed
> the shipped `querydoc` tool made a replacement nearly free; §5.1a of that spec has since shown it
> is a from-source build. With both options costed honestly, "drop the working service" is no longer
> obviously right, and this spec owns that call.
> **Public-safe:** no account ids, no tokens, no client or employer document names, no corpus
> content. The one credential found during the survey is flagged in §4 and named nowhere.
> Facts in §2 were read from the source repository on 2026-10-03, not recalled.

---

## 1. The decision this spec exists to make

Three different things are tangled in "bring the RAG into the platform", and they have different
answers:

1. **The service** — a retrieval chain over a document set. Portable.
2. **The corpus** — the documents it indexes. **Not portable**, see §4.
3. **The surface** — who may ask it questions, and in what shape. This is where the real
   architecture decision lives, and it is not "run the container in EKS".

Getting (3) wrong produces a second chatbot bolted to the side of an agent platform. Getting it
right produces a *tool* the fleet can use, which is a different thing.

---

## 2. What exists today (read from source, 2026-10-03)

| | |
|---|---|
| Shape | FastAPI app, LangChain LCEL chain: retrieve → format → prompt → LLM → parse |
| Vector store | Chroma, `persist_directory=./chroma_db`, ~3.6 MB on disk, `hnsw:space` fixed at creation |
| Embeddings | `AzureOpenAIEmbeddings`, deployment `text-embedding-3-large` |
| Chat model | `AzureChatOpenAI`, same Azure resource |
| Ingestion | `ingest.py` — PDF and .docx loaders, `RecursiveCharacterTextSplitter`, `--rebuild` flag |
| Diagram pass | `diagram_vision.py` — renders PDF pages to images, has a vision model describe them, indexes the description. **The genuinely novel part** |
| Corpus | three documents: two architecture PDFs and one migration proposal |
| HTTP surface | `/health`, `/chat`, `/chat/stream`, `/analytics`, `/evaluation`, plus the `/ops/*` routes added for the Operations tab |
| Eval | `eval/dataset.jsonl` plus four reviewer files — 70 graded questions, 26% unanswerable / false-premise |
| Containerised | **No.** There is no Dockerfile. It has only ever run from a checkout |

Two of those drive most of §5 and §6: **it is not containerised**, and **it is wired to Azure
OpenAI** — which ARIA no longer has.

---

## 3. What comes across, and what does not

| From the group project | Decision | Why |
|---|---|---|
| The retrieval chain | **Take, reshaped** | It works and it is understood. But it comes across as a *retrieval tool*, not a chat chain — §5.2 |
| `ingest.py` loaders + splitter | **Take** | PDF and .docx handling is what doc2vec would have had to be configured to do, and this is already debugged |
| The diagram vision pre-pass | **Take — the reason to do any of this** | Text extraction yields box labels and no topology. Nothing else in ARIA indexes diagram structure, and `spec-corpus-mcp.md` §5.2 already concluded this stays ours under either plan |
| The 70-question eval set | **Already taken** | Phase 1 of `spec-corpus-mcp.md`, built 2026-09-25. Independent of this spec |
| Chroma as the store | **Take for now, with eyes open** | §6.2. It is a directory, which is the same volume problem doc2vec had — but this service owns its own ingestion, so rebuild-on-start is cheap |
| The React chat UI | **Drop** | ARIA is an agent platform, not a chat product. The Operations tab is the human surface that already exists |
| `/analytics` and `/evaluation` | **Drop** | Langfuse owns traces and cost; the promptfoo loop owns eval. Two owners per fact is how this project has drifted before |
| Azure OpenAI wiring | **Drop, mandatory** | §6.1 — the resource was deleted in September. Not a preference |
| **The corpus itself** | **Do not move** | §4. This one changes the architecture, not just the work |

---

## 4. The constraint that shapes everything: the corpus cannot come across

The indexed documents are **employer and client material**. In the source repository both the
documents *and the vector index built from them* are tracked in git.

ARIA is a **public** repository in a **personal** AWS account. Moving either across would mean:

- client material in a personal cloud account, outside any NCS data boundary or agreement;
- no safe middle ground in "just the index" — chunks are recoverable verbatim, so a vector index is
  a copy of the document, not a derivative of it;
- any agent granted the corpus tool can retrieve those chunks, which is a wider reach than the group
  project ever had.

**This is a governance decision, not a technical one, and not mine to make.** Three shapes follow,
and they are genuinely different systems:

| Option | What ARIA indexes | What it demonstrates | Cost |
|---|---|---|---|
| **A. Service, public corpus** | ARIA's own `docs/`, `ARCHITECTURE.md`, `platform/*/README.md` | The platform pattern: a retrieval tool the fleet can query, with the diagram pass over ARIA's own diagrams | Low. No governance question at all |
| **B. Service, private corpus, private deployment** | the client documents | The original assistant, platform-hosted | High. Needs an NCS-side decision, a private registry, a private repo, and a data boundary ARIA does not have |
| **C. Service plus a fixture corpus** | synthetic documents written for the purpose | The retrieval *regression test* — fixed corpus, graded questions | Medium. Someone has to write the fixture |

**Recommendation: A, with C as the eval path.** It keeps the interesting engineering — the diagram
pass, the retrieval tool, the agent wiring — and leaves the client material where it already lives.
`spec-corpus-mcp.md` §4 reached the same conclusion from the other direction: *the reasoning* is the
body of knowledge no existing agent can reach, and that reasoning is ARIA's own design record.

> **Found during the survey, unrelated to the architecture but worth acting on:** the source
> repository's `.env` holds a live Azure API key. It is correctly gitignored and untracked, so it is
> not in git history — but it is a long-lived key sitting in a working directory, for a resource that
> may or may not still exist. Rotate it, or confirm the resource is gone. Named nowhere in this repo.

---

## 5. Architecture

### 5.1 Where it runs

A Deployment we own, in `platform/corpus/`, following the shape every other tool server here uses —
not the kagent chart's `querydoc`, which `spec-corpus-mcp.md` §5.1a showed cannot ingest anything.

```
platform/corpus/
  deployment.yaml       initContainer: ingest -> emptyDir ; container: service reading it
  service.yaml          ClusterIP
  remotemcpserver.yaml  wiring only
  configmap.yaml        corpus source list + chunking parameters
```

**Rebuild-on-start via an initContainer**, for the reason `spec-corpus-mcp.md` §5.2 chose it: the
corpus is small, an `emptyDir` needs no PVC and no node affinity, and rebuilding removes the
staleness question entirely. It costs a slower pod start. `[VERIFY]` the ingest wall-clock against
the real corpus before accepting this — if it runs to minutes rather than seconds, the answer becomes
a `CronJob` plus EFS, which is that spec's option (2) and considerably more moving parts.

**It must be containerised first.** There is no Dockerfile today. That is the first real task, and
it is where the `investigation-loop` lesson applies: **pin the dependency tree**. That agent's image
crashlooped on 2026-10-01 because a rebuild for an unrelated one-line change re-resolved
`opentelemetry-sdk` past a version its own dependency needed. This service's `pyproject.toml`
already carries a deliberate `langchain-community>=0.3.30,<0.4` pin with the reasoning written next
to it — follow that habit for the rest, and build from a lockfile.

### 5.2 How agents reach it — the actual design decision

The service today answers questions: retrieve, then an LLM writes prose with citations. **Do not
expose that to agents.** An agent calling a RAG chain puts two models in series, and the second one
is the one that invents things — precisely the failure `spec-corpus-mcp.md` §3 measured, where three
of four `false_premise` cases failed.

Expose **retrieval**, not answering:

| Tool | Returns |
|---|---|
| `search_corpus(query, k)` | ranked chunks, each with its source path and distance score |
| `get_document_chunks(path, from, to)` | a named document's chunks by index range, for reading around a hit |

The agent does the reasoning; the corpus supplies evidence with provenance. Three things follow:

- **Every chunk carries its source path.** Not decoration: it is what lets the groundedness rubric
  already in the eval loop grade a corpus answer the same way it grades a tool answer.
- **Scores come back raw.** `backend.py` already works to preserve Chroma's distances rather than
  discard them — its `prepare()` deliberately bypasses the LangChain retriever to keep them. Keep
  that; it is what makes "retrieved nothing relevant" distinguishable from "retrieved nothing".
- **The chat chain stays**, serving the Operations tab over HTTP. One service, two surfaces: MCP for
  agents, REST for humans. The second LLM lives on the human path only.

### 5.3 Wiring

`RemoteMCPServer`, because the `MCPServer` CRD's `deployment` block has no volume or initContainer
surface — the same conclusion `spec-corpus-mcp.md` §5.1a reached. This is a legitimate use of
`RemoteMCPServer` for something running *inside* the cluster: "remote" means not managed by that
resource, not off-cluster.

Then, in order: an Istio allow-list naming the principals permitted to reach it (both sides, as with
every other server here), and only then the consuming agents' `toolNames`.

**First consumer: a new read-only agent, not an existing one.** `spec-corpus-mcp.md` §6 proposed
`design-historian` (tier `1-readonly`, corpus only, answers "why is it like this"). That is still
right, and it is now the *only* sensible first consumer — the other candidate, wiring the corpus into
`infra-author` so it checks proposals against prior decisions, depends on `infra-author`, whose write
path is paused on the adk-go bug.

---

## 6. The two things that are not optional

### 6.1 Azure is gone, so the index has to be rebuilt

The service embeds with Azure `text-embedding-3-large`. ARIA deleted its Azure resource in September
and routes all model traffic through the LiteLLM gateway (Bedrock, plus Cohere Embed v4 for
embeddings). Consequences, in order:

1. `AzureOpenAIEmbeddings` / `AzureChatOpenAI` become the OpenAI-compatible clients pointed at the
   gateway. LiteLLM speaks the OpenAI API, so this is a base-URL and model-name change, not a
   rewrite.
2. **The existing `chroma_db` cannot be carried over.** A different embedding model means different
   vector dimensions and a different space; a store built with one model is meaningless to another.
   The index must be rebuilt from source documents — another argument for ingest-on-start, and
   another reason §4's answer has to come first.
3. The corpus becomes the gateway's second consumer after `cost-sentinel`, which is worth having:
   embeddings then land in the same cost and trace plane as everything else.

### 6.2 Chroma is a choice to re-examine, not a given

It is here because it was already working, which is a good enough reason to start. But it is a local
directory, which is why §5.1 needs an initContainer at all. `[VERIFY]` whether Chroma can be pointed
cleanly at a path outside the working directory in a read-only-rootfs container. If that turns
awkward, sqlite-vec and Qdrant are the alternatives — the same two doc2vec offers.

---

## 7. Phases

| Phase | What | Depends on |
|---|---|---|
| **0** | **Answer §4.** Which corpus. Nothing else starts | a decision, not work |
| **1** | Containerise: Dockerfile, pinned deps, builds from a lockfile, runs ingest and serves locally | §4 |
| **2** | Repoint models to the gateway; rebuild the index; confirm retrieval quality has not collapsed against the eval set | phase 1, §6.1 |
| **3** | Deploy: Deployment + Service + `RemoteMCPServer` + Istio allow-list | phase 2 |
| **4** | Add the two MCP tools (§5.2) and wire `design-historian` | phase 3 |
| **5** | `[optional]` wire the corpus into `infra-author`, so proposals are checked against prior decisions | `infra-author` unpaused |

Phases 1 and 2 are testable on a laptop and worth doing even if deployment stalls.

---

## 8. What would change this plan

- **§4 answers "B"** (private corpus) — then this is not an ARIA increment at all. It is an NCS
  deployment, and it belongs in a different repository and account.
- **Ingest takes minutes, not seconds** — rebuild-on-start dies and §5.1 becomes a CronJob plus EFS.
  Measure before building.
- **Retrieval quality collapses on the new embedding model** — then §6.1 step 2 is not a migration
  but a re-tuning exercise, and the eval set is what will say so. The most likely unpleasant surprise.
- **The diagram pass does not survive the model change** — it needs a vision model, so the gateway
  must expose one. `[VERIFY]` against the live gateway's model list before phase 2.
- **`querydoc` gains volume support upstream** — then `spec-corpus-mcp.md`'s plan becomes cheap again
  and this service is the thing to drop. Worth re-checking at each kagent upgrade.

---

## 9. What this spec is not

Not a status document — build state lives in `_STATUS.md`. Not architecture-of-record: if this ships,
the shape change goes to `ARCHITECTURE.md` as a new domain row and the detail to
`platform/corpus/README.md`. Not a commitment past phase 2; each phase should be re-judged on what
the one before it showed.

It also does not decide §4, and should not be read as having done so.
