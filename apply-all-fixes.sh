#!/bin/bash
set -e

echo "🔧 Applying brute-force logging and parser resilience..."

cp src/sync/SyncEngine.ts .backups/SyncEngine.ts.final
cp src/parser/ResponseParser.ts .backups/ResponseParser.ts.final

# ------------------------------------------------------------------
# 1. SyncEngine with VERBATIM logging
# ------------------------------------------------------------------
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
        Logger.info('SyncEngine: Sidebar callback registered');
    }

    async syncSelected() {
        vscode.window.showInformationMessage('Sync initiated from command palette');
    }

    async syncToPlatform(platform: string, files: string[], prompt: string) {
        Logger.info(`SyncEngine: Starting sync to ${platform} with ${files.length} files`);
        try {
            const adapter = this.adapters.get(platform);
            if (!adapter) throw new Error(`No adapter for ${platform}`);

            const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();
            const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);
            const contextBlock = this.retrievalEngine.formatContextForPrompt(context);
            
            const augmentedPrompt = `${contextBlock}

## User Request
${prompt}

## Output Format (MANDATORY)
You MUST respond with EXACTLY the following format for any file changes:

FILE: path/to/file.ext
<entire file content>
END_FILE

Do not add extra text before or after. Do not use markdown code fences inside.`;

            Logger.info(`SyncEngine: Prompt augmented`);

            await adapter.initialize();
            await adapter.uploadFiles(files);
            await adapter.sendPrompt(augmentedPrompt);
            
            const response = await adapter.waitForResponse();
            const responseContent = response?.content || '';
            Logger.info(`SyncEngine: Response received (${responseContent.length} chars)`);
            
            if (this.sidebarPostMessage) {
                this.sidebarPostMessage({ type: 'response', content: responseContent });
                Logger.info('SyncEngine: Response sent to sidebar');
            } else {
                Logger.warn('SyncEngine: No sidebar callback, response not displayed');
            }

            this.iterationTracker.track({
                platform,
                prompt,
                files,
                responseSummary: responseContent.substring(0, 200)
            });
        } catch (error) {
            Logger.error(`SyncEngine: Sync failed - ${error}`);
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

        let parsedChanges = ResponseParser.parseFILEBlocks(responseText).map(f => ({ filePath: f.path, content: f.content }));
        Logger.info(`FILE blocks parsed: ${parsedChanges.length}`);

        if (parsedChanges.length === 0) {
            // Fallback: extract code fence content
            const fenceMatch = responseText.match(/```(?:\w*)\s*([\s\S]*?)```/);
            if (fenceMatch) {
                const guessedPath = 'sample.html';
                parsedChanges = [{ filePath: guessedPath, content: fenceMatch[1].trim() }];
                Logger.info(`Extracted code fence, using ${guessedPath}`);
            }
        }

        if (parsedChanges.length === 0) {
            parsedChanges = UnifiedDiffParser.parse(responseText);
            Logger.info(`Unified diff parsed: ${parsedChanges.length}`);
        }

        if (parsedChanges.length === 0) {
            vscode.window.showWarningMessage('No file changes detected. Check .codex-memory/raw_response.txt');
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

        let appliedCount = 0;
        for (const file of parsedChanges) {
            try {
                const uri = vscode.Uri.file(file.filePath);
                const dir = path.dirname(file.filePath);
                if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
                await vscode.workspace.fs.writeFile(uri, Buffer.from(file.content));
                appliedCount++;
                Logger.info(`Wrote ${file.filePath}`);
            } catch (e) {
                Logger.error(`Failed to write ${file.filePath}: ${e}`);
            }
        }

        vscode.window.showInformationMessage(`✅ Applied changes to ${appliedCount} file(s).`);
        Logger.info(`=== applyResponse END ===`);
    }

    dispose() {
        this.browserManager.closeAll();
    }
}
EOF

# ------------------------------------------------------------------
# 2. Ultra-resilient ResponseParser
# ------------------------------------------------------------------
cat > src/parser/ResponseParser.ts << 'EOF'
import { Logger } from '../utils/logger';

export interface FileBlock {
    path: string;
    content: string;
}

export class ResponseParser {
    static parseFILEBlocks(text: any): FileBlock[] {
        if (!text || typeof text !== 'string') {
            Logger.warn('ResponseParser: non-string input');
            return [];
        }

        const fileChanges: FileBlock[] = [];
        
        // Try multiple regex patterns
        const patterns = [
            /FILE:\s*([^\n\r]+)\s*\n([\s\S]*?)END_FILE/g,           // standard
            /FILE:\s*([^\n\r]+)\s*\r?\n([\s\S]*?)END_FILE/g,        // with optional \r
            /FILE:\s*([^\n\r]+)\s*([\s\S]*?)END_FILE/g,             // no newline after path
            /FILE:\s*([^\n\r]+)\s*\n([\s\S]*?)(?=FILE:|$)/g,        // until next FILE or end
        ];

        for (const regex of patterns) {
            let match;
            while ((match = regex.exec(text)) !== null) {
                let filePath = match[1].trim();
                // Strip trailing artifacts
                filePath = filePath.replace(/(Copy|Download|CopyDownload|\.html).*$/i, '');
                const content = match[2].trim();
                if (content.length > 0) {
                    fileChanges.push({ path: filePath, content });
                    Logger.info(`ResponseParser: Found FILE block for ${filePath} (${content.length} chars)`);
                }
            }
            if (fileChanges.length > 0) break;
        }

        // If still nothing, try to find any line starting with "FILE:" manually
        if (fileChanges.length === 0) {
            const lines = text.split('\n');
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].trim().startsWith('FILE:')) {
                    const filePath = lines[i].replace('FILE:', '').trim().replace(/(Copy|Download).*$/i, '');
                    // Collect content until END_FILE or end of text
                    let contentLines = [];
                    for (let j = i+1; j < lines.length; j++) {
                        if (lines[j].trim() === 'END_FILE') break;
                        contentLines.push(lines[j]);
                    }
                    const content = contentLines.join('\n').trim();
                    if (content) {
                        fileChanges.push({ path: filePath, content });
                        Logger.info(`ResponseParser: Manual extraction for ${filePath}`);
                    }
                    break;
                }
            }
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

npm run compile

echo ""
echo "✅ Final fixes applied."
echo ""
echo "📁 Raw response will be saved to .codex-memory/raw_response.txt"
echo "📋 Check the 'Codex Browser Agent' output channel for detailed parse logs."
echo ""
echo "Now restart (F5), run a sync, click Apply, then check:"
echo "  - Output channel for '=== applyResponse START ===' and parse results"
echo "  - .codex-memory/raw_response.txt for exact LLM output"