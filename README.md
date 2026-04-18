# Codex Browser Agent v3
### 🚀 Powered by [Raxon Labs](https://raxonlabs.com)

**Codex Browser Agent** is a high-performance, autonomous VS Code extension by Raxon Labs that turns your browser-based LLM sessions (ChatGPT, Claude, Gemini, DeepSeek, Grok) into a "Copilot-grade" coding agent.

By leveraging **Playwright** to automate existing browser sessions, it eliminates the need for expensive API keys while providing a sophisticated, agentic coding experience directly within your IDE.

---

## 🚀 Key Features

### 1. Autonomous Agentic Loop (ReAct)
Moves beyond simple prompt-response. The agent operates in a closed loop of **Thought → Action → Observation**. It can autonomously explore your filesystem, list directories, read files, run terminal commands, and apply surgical edits until the task is complete.

### 2. Browser-Native Orchestration (No API Keys)
Directly interfaces with the Web UIs of major LLMs.
*   **Stealth Integration:** Uses advanced browser fingerprinting and stealth injections to bypass Cloudflare Turnstile and anti-bot protections.
*   **Session Persistence:** Reuses existing browser containers to maintain conversation history and login states across multiple iterations.

### 3. Smart Context Selection & RAG
Built for large-scale repositories.
*   **Heuristic Filtering:** Automatically identifies the top 10 most relevant files based on user prompts and active editor focus.
*   **Vector Search:** Optional RAG (Retrieval Augmented Generation) indexing for precise context retrieval in complex architectures.
*   **Surgical Truncation:** Smartly handles massive files by providing relevant head/tail snippets to preserve the LLM's context window.

### 4. Speculative Execution (Shadow Workspace)
Safety first. The agent can spawn a hidden **Shadow Workspace** in your `/tmp/` directory to build, compile, and run its generated code. You only merge the changes back into your main repository after reviewing the unified diff.

### 5. Multi-Language AST Patching
Uses **tree-sitter** for structural code modification, ensuring that blocks are replaced with syntax-perfect precision across TypeScript, Python, Java, and more.

---

## 🛠 Project Architecture

*   **`src/browser/`**: Persistent Playwright browser management and anti-bot stealth.
*   **`src/adapters/`**: Platform-specific logic for DOM extraction and streaming stability.
*   **`src/agent/`**: The core ReAct loop (`AgentLoop`) and Tool Executor.
*   **`src/parser/`**: Resilient response parsing (handles DOM-squashed formatting and UI artifacts).
*   **`src/sync/`**: Coordination engine between the IDE state and the browser agent.

---

## 🚦 Getting Started

### Prerequisites
*   [Node.js](https://nodejs.org/) installed.
*   VS Code installed.

### Installation
1.  Clone the repository:
    ```bash
    git clone https://github.com/your-username/codex-browser-agent.git
    cd codex-browser-agent
    ```
2.  Install dependencies:
    ```bash
    npm install
    ```
3.  Compile the extension:
    ```bash
    npm run compile
    ```

### Usage
1.  Launch the extension (Press `F5` in VS Code).
2.  Open the **Codex Browser Agent** sidebar.
3.  Login to your preferred LLM platform in the browser window that appears.
4.  Select your workspace files, enter a prompt, and watch the agent take control.

---

## ⚖️ License & Credits
Developed with ❤️ by **[Raxon Labs](https://raxonlabs.com)**.

This project is licensed under the MIT License. Explore and build!
