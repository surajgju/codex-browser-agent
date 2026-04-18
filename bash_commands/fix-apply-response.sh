#!/bin/bash
set -e

echo "🔧 Fixing response parsing and adding defensive checks..."

# Backup files
cp src/parser/UnifiedDiffParser.ts src/parser/UnifiedDiffParser.ts.bak
cp src/sync/SyncEngine.ts src/sync/SyncEngine.ts.bak

# 1. Fix UnifiedDiffParser to handle non-string inputs
cat > src/parser/UnifiedDiffParser.ts << 'EOF'
export interface DiffChange {
    filePath: string;
    content: string;
}

export class UnifiedDiffParser {
    static parse(diff: any): DiffChange[] {
        // Guard against non-string inputs
        if (!diff || typeof diff !== 'string') {
            console.warn('UnifiedDiffParser received non-string input:', diff);
            return [];
        }
        
        const files: DiffChange[] = [];
        const blocks = diff.split("diff --git ");
        for (const block of blocks) {
            if (!block.trim()) continue;
            const lines = block.split("\n");
            const fileLine = lines[0];
            const match = fileLine.match(/a\/(.+?) b\/(.+)/);
            if (!match) continue;
            const filePath = match[2];
            const content = lines
                .filter(l => l.startsWith("+") && !l.startsWith("+++"))
                .map(l => l.slice(1))
                .join("\n");
            files.push({ filePath, content });
        }
        return files;
    }
}
EOF

# 2. Fix ResponseParser to handle non-string
cat > src/parser/ResponseParser.ts << 'EOF'
export interface FileBlock {
    path: string;
    content: string;
}

export class ResponseParser {
    static parseFILEBlocks(text: any): FileBlock[] {
        if (!text || typeof text !== 'string') {
            console.warn('ResponseParser received non-string input:', text);
            return [];
        }
        const fileChanges: FileBlock[] = [];
        const regex = /FILE:\s*(.*?)\n([\s\S]*?)END_FILE/g;
        let match;
        while ((match = regex.exec(text)) !== null) {
            fileChanges.push({
                path: match[1].trim(),
                content: match[2]
            });
        }
        return fileChanges;
    }

    static parseCommands(text: any): string[] {
        if (!text || typeof text !== 'string') return [];
        const cmds: string[] = [];
        const regex = /COMMAND:\s*(.*)/g;
        let match;
        while ((match = regex.exec(text)) !== null) {
            cmds.push(match[1]);
        }
        return cmds;
    }
}
EOF

# 3. Fix SyncEngine.applyResponse to add logging and proper type checking
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

            const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);
            const contextBlock = this.retrievalEngine.formatContextForPrompt(context);
            const augmentedPrompt = `${contextBlock}\n\n## User Request\n${prompt}\n\nPlease respond with any code changes in unified diff format (diff --git ...) or FILE: blocks.`;

            Logger.info(`Sync to ${platform} with ${files.length} files, context tokens ~${context.tokenEstimate}`);

            await adapter.initialize();
            await adapter.uploadFiles(files);
            await adapter.sendPrompt(augmentedPrompt);
            
            const response = await adapter.waitForResponse();
            
            // Ensure response.content is a string
            const responseContent = response?.content || '';
            Logger.info(`Response received (${responseContent.length} chars).`);
            
            if (this.sidebarPostMessage) {
                this.sidebarPostMessage({ type: 'response', content: responseContent });
            } else {
                Logger.warn('No sidebar callback set, using command fallback.');
                vscode.commands.executeCommand('codex-browser-agent.applyResponse', { content: responseContent });
            }

            this.iterationTracker.track({
                platform,
                prompt,
                files,
                responseSummary: responseContent.substring(0, 200)
            });

        } catch (error) {
            this.errorHandler.handle(error);
        }
    }

    async applyResponse(responseData: any) {
        Logger.info(`applyResponse called with data type: ${typeof responseData}, keys: ${responseData ? Object.keys(responseData) : 'null'}`);
        
        // Extract the actual response text safely
        let responseText = '';
        if (typeof responseData === 'string') {
            responseText = responseData;
        } else if (responseData && typeof responseData.content === 'string') {
            responseText = responseData.content;
        } else {
            Logger.error('applyResponse received invalid data:', responseData);
            vscode.window.showErrorMessage('Invalid response data received from AI.');
            return;
        }

        if (!responseText.trim()) {
            vscode.window.showWarningMessage('AI response is empty.');
            return;
        }

        let parsedChanges = UnifiedDiffParser.parse(responseText);

        if (parsedChanges.length === 0) {
            const fileBlocks = ResponseParser.parseFILEBlocks(responseText);
            parsedChanges = fileBlocks.map(f => ({ filePath: f.path, content: f.content }));
        }

        if (parsedChanges.length === 0) {
            vscode.window.showWarningMessage('No file changes detected in AI response.');
            Logger.info('Response text was:', responseText.substring(0, 500));
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

# Recompile
npm run compile

echo ""
echo "✅ Fixes applied:"
echo "✔ UnifiedDiffParser now handles non-string inputs safely"
echo "✔ ResponseParser handles non-string inputs"
echo "✔ SyncEngine logs response data type for debugging"
echo "✔ applyResponse extracts content correctly"
echo ""
echo "Now restart the extension host (F5) and test again."
echo "Check the Output panel (Codex Browser Agent) for detailed logs."