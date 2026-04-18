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
import { AgentLoop } from "../agent/AgentLoop";
import { LSPClient } from "../lsp/LSPClient";
import { VectorStore } from "../vector/VectorStore";
import { RetrievalEngine } from '../memory/RetrievalEngine';
import { IterationTracker } from '../memory/IterationTracker';
import { Logger } from '../utils/logger';

export class SyncEngine {
    private browserManager: BrowserManager;
    private adapters: Map<string, PlatformAdapter> = new Map();
    private retrievalEngine: RetrievalEngine;
    private iterationTracker: IterationTracker;
    private sidebarPostMessage?: (message: any) => void;
    private lspClient: LSPClient;
    private vectorStore: VectorStore;

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
        this.lspClient = new LSPClient();
        this.vectorStore = new VectorStore();
        this.lspClient.initialize();
        this.vectorStore.initialize();
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
        Logger.info('SyncEngine: Sidebar callback registered');
    }

    async syncSelected() {
        vscode.window.showInformationMessage('Sync initiated from command palette');
    }

    async syncToPlatform(platform: string, files: string[], prompt: string) {
        Logger.info(`SyncEngine: Using autonomous agent loop for ${platform}`);
        try {
            const adapter = this.adapters.get(platform);
            if (!adapter) throw new Error(`No adapter for ${platform}`);

            const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();
            const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);
            const contextBlock = this.retrievalEngine.formatContextForPrompt(context);
            
            const augmentedPrompt = `${contextBlock}\n\n## User Request\n${prompt}`;

            Logger.info(`SyncEngine: Agent prompt augmented`);
            await adapter.initialize();
            
            const agent = new AgentLoop(adapter, this.lspClient, this.vectorStore);
            await agent.run(augmentedPrompt);

            if (this.sidebarPostMessage) {
                this.sidebarPostMessage({ type: 'response', content: "[Agent loop completed. Check workspace/shadow directories.]" });
                Logger.info('SyncEngine: Agent completion notification sent to sidebar');
            }

            this.iterationTracker.track({
                platform,
                prompt,
                files,
                responseSummary: "Autonomous Agent Execution"
            });
        } catch (error) {
            Logger.error(`SyncEngine: Agent loop failed - ${error}`);
            this.errorHandler.handle(error);
        }
    }

    async applyResponse(responseData: any) {
        Logger.info(`=== applyResponse START ===`);
        let responseText = '';
        if (typeof responseData === 'string') {
            responseText = responseData;
        } else if (responseData && typeof responseData.content === 'string') {
            responseText = responseData.content;
        } else {
            Logger.error('Invalid response data');
            vscode.window.showErrorMessage('Invalid response data');
            return;
        }

        if (!responseText.trim()) {
            vscode.window.showWarningMessage('AI response is empty.');
            return;
        }

        // 🔍 VERBATIM LOGGING – write raw response to file for inspection
        const memPath = path.join(vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || '.', '.codex-memory');
        if (!fs.existsSync(memPath)) fs.mkdirSync(memPath, { recursive: true });
        const rawFile = path.join(memPath, 'raw_response.txt');
        fs.writeFileSync(rawFile, responseText, 'utf8');
        Logger.info(`Raw response written to ${rawFile}`);
        Logger.info(`Response starts with: ${responseText.substring(0, 100)}`);

        const bashScript = ResponseParser.parseBashScript(responseText);

        if (!bashScript) {
            vscode.window.showWarningMessage('No executable bash script detected in AI response. Check .codex-memory/raw_response.txt');
            return;
        }

        const scriptPath = path.join(memPath, 'apply_changes.sh');
        fs.writeFileSync(scriptPath, bashScript, 'utf8');
        Logger.info(`Bash script extracted and written to ${scriptPath}`);

        const choice = await vscode.window.showInformationMessage(
            `Apply changes by executing the generated bash script?`,
            { modal: true },
            'Yes', 'No'
        );

        if (choice === 'Yes') {
            const terminal = vscode.window.createTerminal('Codex Agent (Apply)');
            terminal.show();
            // Ensure the file is executable and run it
            terminal.sendText(`chmod +x "${scriptPath}" && bash "${scriptPath}"`);
            vscode.window.showInformationMessage(`✅ Executing changes script in terminal.`);
        }

        Logger.info(`=== applyResponse END ===`);
    }

    dispose() {
        this.browserManager.closeAll();
    }
}

