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

            // Filter files intelligently before uploading to the browser
            const relevantFiles = await this.selectRelevantFiles(files, prompt);
            
            // If no relevant files found but user selected many, ask user or limit
            if (relevantFiles.length === 0 && files.length > 0) {
                const answer = await vscode.window.showWarningMessage(
                    `Could not automatically select relevant files from ${files.length}. Upload all?`,
                    'Yes, upload all', 'Cancel'
                );
                if (answer !== 'Yes, upload all') return;
                relevantFiles.push(...files.slice(0, 10)); // Limit to safe number
            }

            Logger.info(`SyncEngine: Agent prompt augmented`);
            if (!adapter.initialized) {
                await adapter.initialize();
            }
            
            // Upload only the selected relevant files
            await adapter.uploadFiles(relevantFiles);
            
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

    private async selectRelevantFiles(allFiles: string[], prompt: string): Promise<string[]> {
        const MAX_FILES = 10;          // UI attachment limit
        
        // 1. If total files are small, return all
        if (allFiles.length <= MAX_FILES) return allFiles;

        // 2. Use vector search if available
        let relevant: { path: string; score: number }[] = [];
        if (this.vectorStore) {
            for (const file of allFiles) {
                // Index file if not already indexed (best effort)
                await this.vectorStore.indexFile(file);
            }
            const results = await this.vectorStore.search(prompt, MAX_FILES);
            relevant = results.map(r => ({ path: r.filePath, score: r.score }));
        }

        // 3. Fallback: keyword matching on filename + extension priority
        if (relevant.length === 0) {
            const promptWords = prompt.toLowerCase().split(/\W+/);
            relevant = allFiles.map(file => {
                const lower = file.toLowerCase();
                let score = 0;
                for (const word of promptWords) {
                    if (lower.includes(word)) score += 10;
                }
                // Boost files open in editor
                if (vscode.window.activeTextEditor?.document.uri.fsPath === file) score += 50;
                // Boost based on extension (source files first)
                if (/\.(ts|js|py|java|go|rs|cpp|c)$/.test(file)) score += 5;
                return { path: file, score };
            }).sort((a, b) => b.score - a.score);
        }

        // 4. Take top MAX_FILES
        const selected = relevant.slice(0, MAX_FILES).map(r => r.path);
        Logger.info(`SyncEngine: Selected ${selected.length} relevant files out of ${allFiles.length}`);
        return selected;
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

