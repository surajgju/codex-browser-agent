# Codex Browser Agent - Project Context

## 1. Project Overview & Architecture (Production IDE Agent)
**Codex Browser Agent v3** has evolved into a fully autonomous, multi-language IDE coding agent capable of competing with OpenAI Codex and Copilot. Rather than statically generating code snippets, it uses a closed **Agentic Loop (ReAct)** running via **Playwright**, manipulating ChatGPT, Claude, Gemini, DeepSeek, or Grok sessions.

The entry point is `src/extension.ts`, which wires up structural features:
*   `SidebarProvider`: Renders the VS Code Webview sidebar control UI. Contains Inline Ghost Text hover logic.
*   `SyncEngine`: Replaces raw syncs with the `AgentLoop`, coordinating state between the extension's `LSPClient`, `VectorStore`, and the Browser Adapter.
*   `AgentLoop` & `ToolExecutor`: The brain of the agent. Operates on a `Thought -> Action -> Observation` loop handling live filesystem interactions autonomously.
*   `ShadowWorkspace`: Supports speculative, isolated executions where the agent can build/compile code via arbitrary bash scripts before the user explicitly diffs and accepts the changes into the working repo.

---

## 2. Browser & Adapter Logic (`src/browser/` and `src/adapters/`)
Specific websites have their own Playwright adapters. Critical production mechanisms:
*   **Anti-Bot Stealth:** `BrowserManager.ts` leverages `addInitScript` to strip automation flags and fake navigator fingerprints to seamlessly bypass Cloudflare Turnstile blocks.
*   **Streaming Length-Stability Polling:** Replaces brittle UI button scraping (`stop` buttons). It uses a fast 1s temporal loop recording `.textContent` byte lengths, resolving when the AI output sits perfectly static for 4 consecutive seconds.

---

## 3. Autonomous Execution & Output Parsing MUST-KNOWs
The extension no longer expects the LLM to spit out a single `cat > file` bash script. It expects structured commands mimicking a terminal operator.

### ⚠️ ReAct JSON Tools & ToolExecutor
The `AgentLoop` injects a strict system prompt demanding JSON responses: `{"thought": "...", "action": "tool_name", "actionInput": {...}}`
The `ToolExecutor` acts on behalf of the AI. Tools include:
*   `read_file`, `list_dir`, `search_regex`, `run_command` (terminal read/write), `replace_content`, `ask_user`.
The Agent continues to cycle until it outputs an observation containing `"GOAL_ACHIEVED"`.

### ⚠️ Output Parsing Fallbacks (`ResponseParser.ts`)
When the LLM hallucinates outside the JSON box, or attempts unified diffs/AST patching:
*   Extracting `.textContent` from the browser DOM often squashes and explicitly deletes Markdown Fences (````diff`), breaking standard regex.
*   `ResponseParser.ts` uses highly resilient fallback regex. e.g. If `` ```diff `` disappears, the parser strictly looks for `--- a/` and `+++ b/` boundaries characteristic of git diffs before triggering the `DiffApplier.ts`.
*   Similar boundary-fallbacks exist for AST replacements (`AST_PATCH:`).

---

## 4. Key Next-Gen Capabilities
*   **RAG & Vector Storage:** Uses `src/vector/VectorStore.ts` to chunk and embed codebases locally (simplification strategy deployed, standardizes on keyword-matching/HNSW).
*   **AST Patching:** Uses `tree-sitter` inside `DiffApplier` to surgically drop logic into huge files without corrupting surrounding curly-brace boundaries.

## 5. Extension Commands
*   `codex-browser-agent.openSidebar`
*   `codex-browser-agent.syncSelected`: Initiates the AgentLoop flow.
*   `codex-browser-agent.speculativeApply`: Spawns a hidden `/tmp/` shadow environment, runs arbitrary code, and surfaces a VS Code diff view for acceptance.
*   `codex-browser-agent.agentLoop`: Command palette fallback.

## Summary for AI modifying this project:
1.  **Adding Agent Tools:** Add logic to `ToolExecutor.ts` and update the system prompt in `AgentLoop.ts`.
2.  **Parser/UI Breakage:** If the web UI updates, Playwright DOM extraction might squash fields. ALWAYS put headless fallback regexes inside `ResponseParser.ts`.
3.  **Cloudflare blocks:** Update Stealth arguments inside `BrowserManager.launch()`.
