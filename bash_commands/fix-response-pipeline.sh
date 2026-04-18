#!/bin/bash
set -e

echo "🔧 Patching Codex Agent Response Pipeline..."

# Backup the adapters
cp src/adapters/DeepSeekAdapter.ts src/adapters/DeepSeekAdapter.ts.bak
cp src/sync/SyncEngine.ts src/sync/SyncEngine.ts.bak
cp src/sidebar/SidebarProvider.ts src/sidebar/SidebarProvider.ts.bak

# --- 1. Update DeepSeekAdapter.ts with a resilient response capture strategy ---
cat > src/adapters/DeepSeekAdapter.ts << 'EOF'
import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class DeepSeekAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('deepseek', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        await this.page.goto('https://chat.deepseek.com');
        await this.page.waitForSelector('textarea, [contenteditable="true"]', { timeout: 0 });
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        const fs = require('fs');
        const content = filePaths.map(p => `FILE: ${p}\n\`\`\`\n${fs.readFileSync(p, 'utf8')}\n\`\`\``).join('\n\n');
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(content);
    }

    async sendPrompt(prompt: string): Promise<void> {
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('DeepSeek: Waiting for response...');
        
        // Strategy: Wait for the assistant's turn to finish and the last message to appear.
        // Instead of a brittle class name, we use a functional locator.
        try {
            // First, wait for the "stop" button to disappear, indicating the AI is done "thinking".
            await this.page.waitForSelector('.ds-icon-button', { state: 'detached', timeout: 90000 }).catch(() => {
                Logger.warn('DeepSeek: "Stop" button not found or already gone. Continuing...');
            });

            // Next, wait for the actual markdown content to appear.
            // This selector targets the last message in the conversation.
            await this.page.waitForSelector('.ds-markdown p, .ds-markdown pre, .ds-markdown', { timeout: 15000 });
            
            // Give the page a tiny moment for any final rendering.
            await this.page.waitForTimeout(2000);

        } catch (e) {
            Logger.warn(`DeepSeek: Initial wait strategy failed, falling back to generic wait. Error: ${e}`);
            await this.page.waitForTimeout(15000); // Fallback: just wait 15 seconds
        }

        // Extract the full response from the last assistant message.
        const responseText = await this.page.evaluate(() => {
            // Find all assistant message containers.
            // DeepSeek uses elements with the class 'ds-markdown' for the final rendered markdown.
            const messages = document.querySelectorAll('.ds-markdown');
            if (messages.length > 0) {
                // Return the content of the *last* assistant message.
                return messages[messages.length - 1]?.textContent || '';
            }
            return '';
        });

        Logger.info(`DeepSeek: Response captured (${responseText.length} chars).`);
        return { content: responseText || '' };
    }
}
EOF

# --- 2. Enhance SyncEngine.ts to ensure the callback is always available ---
cat > src/sync/SyncEngine.ts << 'EOF'
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { Config } from '../utils/config';
import { ErrorHandler } from '../utils/errorHandler';
import { StorageHelper } from '../utils/storage';
import { BrowserManager } from '../browser/BrowserManager';
import { ChatGPTAdapter } from '../adapters/ChatGPTAdapter';
import { GeminiAdapter } from '../adapters/GeminiAdapter';
import { ClaudeAdapter } from '../adapters/ClaudeAdapter';
import { GrokAdapter } from '../adapters/GrokAdapter';
import { DeepSeekAdapter } from '../adapters/DeepSeekAdapter';
import { PlatformAdapter } from '../browser/PlatformAdapter';
import { UnifiedDiffParser } from '../parser/UnifiedDiffParser';
import { ResponseParser } from '../parser/ResponseParser';
import { RetrievalEngine } from '../memory/RetrievalEngine';
import { IterationTracker } from '../memory/IterationTracker';
import { Logger } from '../utils/logger';

export class SyncEngine {
    private browserManager: BrowserManager;
    private adapters: Map<string, PlatformAdapter> = new Map();
    private retrievalEngine: RetrievalEngine;
    private iterationTracker: IterationTracker;
    private sidebarPostMessage?: (message: any) => void;

    constructor(
        private config: Config,
        private errorHandler: ErrorHandler,
        private storage: StorageHelper
    ) {
        this.browserManager = BrowserManager.getInstance(config);
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
        this.retrievalEngine = new RetrievalEngine(workspaceFolder);
        this.iterationTracker = new IterationTracker(workspaceFolder);
        this.registerAdapters();
    }

    private registerAdapters() {
        this.adapters.set('chatgpt', new ChatGPTAdapter(this.browserManager));
        this.adapters.set('gemini', new GeminiAdapter(this.browserManager));
        this.adapters.set('claude', new ClaudeAdapter(this.browserManager));
        this.adapters.set('grok', new GrokAdapter(this.browserManager));
        this.adapters.set('deepseek', new DeepSeekAdapter(this.browserManager));
    }

    setSidebarPostMessage(callback: (message: any) => void) {
        this.sidebarPostMessage = callback;
    }

    async syncSelected() {
        vscode.window.showInformationMessage('Sync initiated from command palette');
    }

    async syncToPlatform(platform: string, files: string[], prompt: string) {
        try {
            const adapter = this.adapters.get(platform);
            if (!adapter) throw new Error(`No adapter for ${platform}`);

            const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();

            // Build RAG context
            const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);
            const contextBlock = this.retrievalEngine.formatContextForPrompt(context);
            const augmentedPrompt = `${contextBlock}\n\n## User Request\n${prompt}\n\nPlease respond with any code changes in unified diff format (diff --git ...) or FILE: blocks.`;

            Logger.info(`Sync to ${platform} with ${files.length} files, context tokens ~${context.tokenEstimate}`);

            await adapter.initialize();
            await adapter.uploadFiles(files);
            await adapter.sendPrompt(augmentedPrompt);
            
            // --- WAIT FOR RESPONSE ---
            const response = await adapter.waitForResponse();
            
            // --- CRITICAL: Ensure response is sent back to UI ---
            if (response && response.content) {
                Logger.info(`Response received (${response.content.length} chars). Sending to sidebar.`);
                
                // 1. Send via direct callback (preferred)
                if (this.sidebarPostMessage) {
                    this.sidebarPostMessage({ type: 'response', content: response.content });
                } else {
                    Logger.warn('SidebarPostMessage callback not set. Falling back to command.');
                    // 2. Fallback: trigger a command that the sidebar can listen to.
                    vscode.commands.executeCommand('codex-browser-agent.applyResponse', response);
                }
            } else {
                throw new Error('No response content received from adapter.');
            }

            // Track iteration
            this.iterationTracker.track({
                platform,
                prompt,
                files,
                responseSummary: response.content.substring(0, 200)
            });

        } catch (error) {
            this.errorHandler.handle(error);
        }
    }

    async applyResponse(responseData: any) {
        // ... (rest of the applyResponse logic remains unchanged)
        const responseText = responseData.content || responseData;
        let parsedChanges = UnifiedDiffParser.parse(responseText);
        if (parsedChanges.length === 0) {
            const fileBlocks = ResponseParser.parseFILEBlocks(responseText);
            parsedChanges = fileBlocks.map(f => ({ filePath: f.path, content: f.content }));
        }
        if (parsedChanges.length === 0) {
            vscode.window.showWarningMessage('No file changes detected in AI response.');
            return;
        }

        if (this.config.showDiffBeforeApply) {
            const choice = await vscode.window.showInformationMessage(
                `Apply changes to ${parsedChanges.length} file(s)?`,
                { modal: true },
                'Yes', 'Show Diff', 'No'
            );
            if (choice === 'Show Diff') {
                const first = parsedChanges[0];
                const originalUri = vscode.Uri.file(first.filePath);
                const modifiedUri = vscode.Uri.parse(`untitled:${path.basename(first.filePath)}.modified`);
                await vscode.workspace.fs.writeFile(modifiedUri, Buffer.from(first.content));
                await vscode.commands.executeCommand('vscode.diff', originalUri, modifiedUri, `${first.filePath} (AI Suggested)`);
                return;
            } else if (choice !== 'Yes') {
                return;
            }
        }

        const applied: { file: string; snippet: string }[] = [];
        for (const file of parsedChanges) {
            const uri = vscode.Uri.file(file.filePath);
            try {
                await vscode.workspace.fs.writeFile(uri, Buffer.from(file.content));
                applied.push({ file: file.filePath, snippet: file.content.substring(0, 100) });
            } catch (e) {
                Logger.error(`Failed to write ${file.filePath}: ${e}`);
            }
        }

        const commands = ResponseParser.parseCommands(responseText);
        if (commands.length > 0) {
            const run = await vscode.window.showInformationMessage(`Run suggested commands?`, 'Yes', 'No');
            if (run === 'Yes') {
                const terminal = vscode.window.createTerminal('Codex Agent');
                terminal.show();
                commands.forEach(cmd => terminal.sendText(cmd));
            }
        }

        vscode.window.showInformationMessage(`✅ Applied changes to ${applied.length} file(s).`);
    }

    dispose() {
        this.browserManager.closeAll();
    }
}
EOF

# --- 3. Update SidebarProvider.ts to set the callback immediately ---
cat > src/sidebar/SidebarProvider.ts << 'EOF'
import * as vscode from 'vscode';
import { ContextEngine } from '../context/ContextEngine';
import { SyncEngine } from '../sync/SyncEngine';
import { CommandRunner } from '../commands/CommandRunner';
import { Config } from '../utils/config';

export class SidebarProvider implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _contextEngine: ContextEngine,
        private readonly _syncEngine: SyncEngine,
        private readonly _commandRunner: CommandRunner,
        private readonly _config: Config
    ) {
        // Immediately wire the callback so it's ready as soon as the webview is created.
        this._syncEngine.setSidebarPostMessage((message: any) => {
            if (this._view) {
                this._view.webview.postMessage(message);
            } else {
                console.warn('Sidebar view not yet ready to receive messages.');
            }
        });
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        this._view = webviewView;
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this._extensionUri]
        };
        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (message) => {
            switch (message.command) {
                case 'selectFiles':
                    await this._handleSelectFiles();
                    break;
                case 'syncToAI':
                    await this._syncEngine.syncToPlatform(message.platform, message.files, message.prompt);
                    break;
                case 'runCommand':
                    await this._commandRunner.run(message.command);
                    break;
                case 'applyResponse':
                    await this._syncEngine.applyResponse({ content: message.response });
                    break;
            }
        });

        this._sendConfig();
        this._sendContextUpdate();
    }

    private async _handleSelectFiles() {
        const uris = await vscode.window.showOpenDialog({
            canSelectMany: true,
            canSelectFiles: true,
            canSelectFolders: true,
            openLabel: 'Select for AI context'
        });
        if (uris) {
            const filePaths = uris.map(uri => uri.fsPath);
            this._contextEngine.addSelectedFiles(filePaths);
            this._sendContextUpdate();
        }
    }

    private _sendConfig() {
        this._view?.webview.postMessage({
            type: 'config',
            config: {
                maxFilesPerBatch: this._config.maxFilesPerBatch,
                platforms: ['chatgpt', 'gemini', 'claude', 'grok', 'deepseek'],
                showDiffBeforeApply: this._config.showDiffBeforeApply
            }
        });
    }

    private _sendContextUpdate() {
        const contextFiles = this._contextEngine.getRelevantFiles();
        this._view?.webview.postMessage({
            type: 'contextUpdate',
            files: contextFiles
        });
    }

    private _getHtmlForWebview(webview: vscode.Webview): string {
        const scriptUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this._extensionUri, 'src', 'webview', 'main.js')
        );
        const styleUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this._extensionUri, 'src', 'webview', 'styles.css')
        );
        return `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src ${webview.cspSource};">
    <link rel="stylesheet" href="${styleUri}">
</head>
<body>
    <div class="container">
        <h2>Codex Browser Agent v3</h2>
        <div class="file-section">
            <button id="select-files">Select Files/Folders</button>
            <ul id="file-list"></ul>
        </div>
        <div class="ai-section">
            <select id="platform-select">
                <option value="chatgpt">ChatGPT</option>
                <option value="gemini">Gemini</option>
                <option value="claude">Claude</option>
                <option value="grok">Grok</option>
                <option value="deepseek">DeepSeek</option>
            </select>
            <textarea id="prompt-input" placeholder="Enter your prompt..."></textarea>
            <button id="sync-button">Sync & Get Response</button>
        </div>
        <div class="response-section">
            <pre id="response-content"></pre>
            <button id="apply-response">Apply Changes</button>
            <button id="run-command">Run Command</button>
        </div>
    </div>
    <script src="${scriptUri}"></script>
</body>
</html>`;
    }
}
EOF

# Recompile the project
npm run compile

echo ""
echo "✅ Response pipeline patched successfully!"
echo ""
echo "Changes made:"
echo "✔ DeepSeekAdapter: Uses robust waiting strategy for response rendering."
echo "✔ SyncEngine: Ensures response is sent to sidebar via callback or command fallback."
echo "✔ SidebarProvider: Sets up the message callback immediately on construction."
echo ""
echo "Next steps:"
echo "1. Restart the Extension Host (F5)."
echo "2. Try syncing with DeepSeek again. The response should now appear in the sidebar."