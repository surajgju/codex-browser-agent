# Codex Browser Agent

Semi‑automatic coding agent using browser‑session reuse (no API keys) with ChatGPT, Gemini, Claude, Grok, DeepSeek.

## Installation

1. Clone or download this repository.
2. Run `npm install` to install dependencies.
3. Run `npm run compile` to build the extension.
4. Press `F5` in VS Code to launch a new Extension Development Host window.

## Usage

- Click the Codex Agent icon in the activity bar to open the sidebar.
- Select files/folders using the "Select Files/Folders" button.
- Choose a platform (ChatGPT, Gemini, etc.), enter a prompt, and click "Sync & Get Response".
- The response will appear; you can apply changes or run suggested commands.

## Configuration

Open VS Code settings (`Cmd+,`) and search for "Codex Browser Agent" to adjust:
- Maximum files per batch
- Allowed terminal commands
- Git auto‑stage behavior
- Diff preview before applying changes
- Custom browser path

## Requirements

- Node.js 18+
- VS Code 1.85+
- Playwright browsers installed automatically via `npx playwright install`
- Active login sessions in the respective AI platforms (manual login required first time)

## macOS Compatibility

The extension uses Playwright's Chromium, which works seamlessly on macOS. Persistent browser contexts store login sessions in `.codex-browser-data` within your workspace (or temp directory if no workspace is open).

## Building and Packaging

```bash
npm install -g @vscode/vsce
npm run package
