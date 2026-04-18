import * as vscode from 'vscode';
import { ContextEngine } from '../context/ContextEngine';
import { SyncEngine } from '../sync/SyncEngine';
import { CommandRunner } from '../commands/CommandRunner';
import { Config } from '../utils/config';
import { Logger } from '../utils/logger';

export class SidebarProvider implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _contextEngine: ContextEngine,
        private readonly _syncEngine: SyncEngine,
        private readonly _commandRunner: CommandRunner,
        private readonly _config: Config
    ) {
        this._syncEngine.setSidebarPostMessage((message: any) => {
            Logger.info(`Sidebar: Posting message type ${message.type} to webview`);
            if (this._view) {
                this._view.webview.postMessage(message);
            } else {
                Logger.warn('Sidebar: View not ready, message dropped');
            }
        });
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        Logger.info('Sidebar: Resolving webview');
        this._view = webviewView;
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this._extensionUri]
        };
        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (message) => {
            Logger.info(`Sidebar: Received message command: ${message.command}`);
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
                    Logger.info(`Sidebar: applyResponse with response length ${message.response?.length || 0}`);
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
            Logger.info(`Sidebar: Selected ${filePaths.length} files`);
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
            <textarea id="response-content" spellcheck="false" placeholder="LLM response will appear here..."></textarea>
            <button id="apply-response">Apply Changes</button>
            <button id="run-command">Run Command</button>
        </div>
    </div>
    <script src="${scriptUri}"></script>
</body>
</html>`;
    }
}
