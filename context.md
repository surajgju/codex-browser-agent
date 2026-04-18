# Codex Browser Agent - Project Context

## 1. Project Overview & Architecture
**Codex Browser Agent** is a VS Code extension (v3) that operates as a semi-automatic AI coding assistant. It uses **Playwright** to hijack existing user browser sessions, bypassing the need for paid API keys. It directly manipulates the DOM of ChatGPT, Claude, Gemini, DeepSeek, or Grok.

The entry point is `src/extension.ts`, which instantiates:
*   `SidebarProvider`: Renders the VS Code Webview sidebar UI (features an interactive textarea for reviewing/editing LLM scripts directly).
*   `ContextEngine` & `FileWatcher`: Tracks what files are open/selected.
*   `WorkspaceMap`: Generates a repository memory map on load.
*   `SyncEngine`: Coordinates gathering file contexts, sending them to the LLM (via the Browser logic), and applying the parsed response back.
*   `CommandRunner`: Executes suggested bash commands based on a whitelist.

---

## 2. Browser & Adapter Logic (`src/browser/` and `src/adapters/`)
All LLM automation stems from `src/browser/PlatformAdapter.ts`.
Specific websites have their own adapters. Critical recent evolutions include:
*   **Anti-Bot Stealth:** `BrowserManager.ts` leverages `addInitScript` to override `navigator.webdriver` and injects argument flags (`--disable-blink-features=AutomationControlled`) to seamlessly bypass Cloudflare Turnstile blocks.
*   **Streaming Length-Stability Polling:** Instead of relying on brittle UI buttons (like `<button>Stop</button>`), all adapters (`DeepSeek`, `ChatGPT`, `Gemini`, `Grok`) now use a 120-second polling loop that extracts `.textContent`. It only resolves when the string byte-length has remained static for 4 consecutive seconds. This completely eliminates truncation bugs caused by UI layout changes.

---

## 3. Parsing and Output Format MUST-KNOWs (`src/parser/`)
The LLM responses are parsed by `ResponseParser.ts`.

### ⚠️ CRITICAL: Bash Script Extraction & DOM Squashing
During recent upgrades, the parser pivoted from analyzing standard `FILE:` tags to **exclusively extracting executable bash scripts.**
However, because extracting `.textContent` from the browser DOM often squashes and removes Markdown Fences (````bash`), the parser uses a highly resilient fallback regex:
*   The LLM provides a `bash` script using tools like `cat > path.js << 'EOF'`.
*   The Web UI rendering often strips the backticks and Prepends UI buttons (`bash`, `Copy`, `Download`).
*   `ResponseParser.parseBashScript` forcefully strips sequential UI artifacts from the start of the string using a `(?:...)+` regex and treats the remaining block as the executable script.

**Workflow Summary:**
1. LLM spits out `cat > ...` bash logic.
2. Web UI exposes it as `bashCopyDownloadcat > ...`.
3. `ResponseParser` strips `bashCopyDownload`. 
4. `SidebarProvider` injects the script into the webview `textarea` natively (allowing user-edits).
5. User clicks "Apply Changes", overwriting `.codex-memory/apply_changes.sh` and running it natively in VS Code's terminal.

---

## 4. Extension Commands
Registered commands in `package.json` that bind the logic together:
*   `codex-browser-agent.openSidebar`
*   `codex-browser-agent.syncSelected`: Initiates the prompt/file context flow.
*   `codex-browser-agent.applyResponse`: Triggers `SyncEngine` script execution.
*   `codex-browser-agent.runCommand`: Triggers `CommandRunner`.

## Summary for AI modifying this project:
1.  **Sync/Wait bugs:** Check adapter `.textContent` stability logic or selector classes.
2.  **Parsing bugs:** Check `ResponseParser.ts` for regex collision regarding UI artifacts (like `CopyDownload`).
3.  **Cloudflare/Login blocks:** Adjust stealth arguments in `BrowserManager.ts`.
