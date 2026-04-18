#!/bin/bash
set -e

echo "🧠 Upgrading Codex Browser Agent to v3 (Memory + RAG)..."
echo "⚠️  This script patches existing source files. Make sure you have committed your changes or backed up."

# ------------------------------------------------------------
# 1. Create memory module directories and files
# ------------------------------------------------------------
mkdir -p src/memory
mkdir -p .codex-memory/summaries
mkdir -p .codex-memory/skills

cat > src/memory/MemoryEngine.ts << 'EOF'
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

export class MemoryEngine {
    private base: string;

    constructor(workspaceFolder?: string) {
        this.base = workspaceFolder
            ? path.join(workspaceFolder, ".codex-memory")
            : path.join(vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd(), ".codex-memory");
        if (!fs.existsSync(this.base)) {
            fs.mkdirSync(this.base, { recursive: true });
        }
    }

    private getPath(name: string): string {
        return path.join(this.base, name);
    }

    load(name: string): any {
        const filePath = this.getPath(name);
        if (!fs.existsSync(filePath)) return name.includes("log") ? [] : {};
        const content = fs.readFileSync(filePath, "utf8");
        try {
            return JSON.parse(content);
        } catch {
            return name.includes("log") ? [] : {};
        }
    }

    save(name: string, data: any): void {
        const filePath = this.getPath(name);
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
    }

    append(name: string, item: any): void {
        const data = this.load(name);
        if (!Array.isArray(data)) {
            this.save(name, [item]);
            return;
        }
        data.push(item);
        // Keep only last 50 iterations to prevent bloat
        if (data.length > 50) {
            data.shift();
        }
        this.save(name, data);
    }
}
EOF

cat > src/memory/IterationTracker.ts << 'EOF'
import { MemoryEngine } from "./MemoryEngine";

export interface IterationEntry {
    timestamp: string;
    platform: string;
    prompt: string;
    files: string[];
    responseSummary?: string;
    appliedChanges?: { file: string; snippet: string }[];
    commandsRun?: string[];
}

export class IterationTracker {
    private memory: MemoryEngine;

    constructor(workspaceFolder?: string) {
        this.memory = new MemoryEngine(workspaceFolder);
    }

    track(entry: Omit<IterationEntry, "timestamp">): void {
        const record: IterationEntry = {
            ...entry,
            timestamp: new Date().toISOString()
        };
        this.memory.append("iteration-log.json", record);
    }

    getRecent(limit: number = 5): IterationEntry[] {
        const all = this.memory.load("iteration-log.json") as IterationEntry[];
        return all.slice(-limit);
    }
}
EOF

cat > src/memory/WorkspaceMap.ts << 'EOF'
import * as fs from "fs";
import * as path from "path";

export class WorkspaceMap {
    generate(dir: string, ignorePatterns: RegExp[] = [/node_modules/, /\.git/, /\.codex-/, /dist/, /out/]): string[] {
        const map: string[] = [];
        const scan = (currentDir: string) => {
            if (!fs.existsSync(currentDir)) return;
            const entries = fs.readdirSync(currentDir);
            for (const entry of entries) {
                const full = path.join(currentDir, entry);
                if (ignorePatterns.some(p => p.test(full))) continue;
                if (fs.statSync(full).isDirectory()) {
                    scan(full);
                } else {
                    map.push(full);
                }
            }
        };
        scan(dir);
        return map;
    }

    getFileTree(dir: string, maxDepth: number = 3): string {
        const lines: string[] = [];
        const scan = (currentDir: string, depth: number, prefix: string = "") => {
            if (depth > maxDepth) return;
            const entries = fs.readdirSync(currentDir).filter(e => !e.startsWith(".") && e !== "node_modules" && e !== ".git");
            for (let i = 0; i < entries.length; i++) {
                const entry = entries[i];
                const full = path.join(currentDir, entry);
                const isLast = i === entries.length - 1;
                const stats = fs.statSync(full);
                lines.push(`${prefix}${isLast ? "└── " : "├── "}${entry}${stats.isDirectory() ? "/" : ""}`);
                if (stats.isDirectory()) {
                    scan(full, depth + 1, prefix + (isLast ? "    " : "│   "));
                }
            }
        };
        scan(dir, 0);
        return lines.join("\n");
    }
}
EOF

cat > src/memory/SkillLoader.ts << 'EOF'
import * as fs from "fs";
import * as path from "path";

export interface Skill {
    name: string;
    description: string;
    triggerKeywords: string[];
    promptTemplate: string;
    contextTemplate?: string;
    postActions?: { type: "command" | "prompt"; value: string }[];
}

export class SkillLoader {
    private skillsDir: string;

    constructor(workspaceFolder?: string) {
        this.skillsDir = path.join(workspaceFolder || process.cwd(), ".codex-memory/skills");
    }

    loadSkills(): Skill[] {
        if (!fs.existsSync(this.skillsDir)) return [];
        return fs.readdirSync(this.skillsDir)
            .filter(f => f.endsWith(".json"))
            .map(f => {
                try {
                    return JSON.parse(fs.readFileSync(path.join(this.skillsDir, f), "utf8")) as Skill;
                } catch {
                    return null;
                }
            })
            .filter((s): s is Skill => s !== null);
    }

    findRelevantSkills(prompt: string): Skill[] {
        const skills = this.loadSkills();
        const lowerPrompt = prompt.toLowerCase();
        return skills.filter(skill =>
            skill.triggerKeywords.some(kw => lowerPrompt.includes(kw.toLowerCase()))
        );
    }
}
EOF

cat > src/memory/RetrievalEngine.ts << 'EOF'
import { MemoryEngine } from "./MemoryEngine";
import { SkillLoader, Skill } from "./SkillLoader";
import { WorkspaceMap } from "./WorkspaceMap";
import { IterationTracker, IterationEntry } from "./IterationTracker";

export interface AugmentedContext {
    recentIterations: IterationEntry[];
    relevantSkills: Skill[];
    workspaceTree: string;
    decisions: any[];
    tokenEstimate: number;
}

export class RetrievalEngine {
    private memory: MemoryEngine;
    private skillLoader: SkillLoader;
    private workspaceMap: WorkspaceMap;
    private iterationTracker: IterationTracker;

    constructor(workspaceFolder?: string) {
        this.memory = new MemoryEngine(workspaceFolder);
        this.skillLoader = new SkillLoader(workspaceFolder);
        this.workspaceMap = new WorkspaceMap();
        this.iterationTracker = new IterationTracker(workspaceFolder);
    }

    buildContext(prompt: string, workspaceRoot: string): AugmentedContext {
        const recentIterations = this.iterationTracker.getRecent(3);
        const relevantSkills = this.skillLoader.findRelevantSkills(prompt);
        const workspaceTree = this.workspaceMap.getFileTree(workspaceRoot, 3);
        const decisions = this.memory.load("decisions.json") as any[];

        // Rough token estimate (4 chars ~ 1 token)
        const contextString = JSON.stringify({ recentIterations, relevantSkills, workspaceTree, decisions });
        const tokenEstimate = Math.ceil(contextString.length / 4);

        return {
            recentIterations,
            relevantSkills,
            workspaceTree,
            decisions: Array.isArray(decisions) ? decisions : [],
            tokenEstimate
        };
    }

    formatContextForPrompt(context: AugmentedContext, maxTokens: number = 2000): string {
        let parts: string[] = [];

        if (context.workspaceTree) {
            parts.push("## Project Structure\n```\n" + context.workspaceTree + "\n```");
        }

        if (context.recentIterations.length > 0) {
            parts.push("## Recent Iterations\n" + context.recentIterations.map(i =>
                `- [${i.timestamp}] ${i.platform}: ${i.prompt.substring(0, 100)}...`
            ).join("\n"));
        }

        if (context.relevantSkills.length > 0) {
            parts.push("## Available Skills\n" + context.relevantSkills.map(s =>
                `- ${s.name}: ${s.description}`
            ).join("\n"));
        }

        let combined = parts.join("\n\n");
        // Truncate if exceeds approximate token limit
        if (combined.length > maxTokens * 4) {
            combined = combined.substring(0, maxTokens * 4) + "\n... (context truncated)";
        }
        return combined;
    }
}
EOF

# ------------------------------------------------------------
# 2. Patch SyncEngine.ts to use memory
# ------------------------------------------------------------
echo "Patching src/sync/SyncEngine.ts..."

# Backup original
cp src/sync/SyncEngine.ts src/sync/SyncEngine.ts.v2.bak

# We'll replace the entire file with an enhanced version that includes memory
cat > src/sync/SyncEngine.ts << 'EOF'
import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import { Config } from "../utils/config";
import { ErrorHandler } from "../utils/errorHandler";
import { StorageHelper } from "../utils/storage";
import { BrowserManager } from "../browser/BrowserManager";
import { ChatGPTAdapter } from "../adapters/ChatGPTAdapter";
import { GeminiAdapter } from "../adapters/GeminiAdapter";
import { ClaudeAdapter } from "../adapters/ClaudeAdapter";
import { GrokAdapter } from "../adapters/GrokAdapter";
import { DeepSeekAdapter } from "../adapters/DeepSeekAdapter";
import { PlatformAdapter } from "../browser/PlatformAdapter";
import { UnifiedDiffParser } from "../parser/UnifiedDiffParser";
import { ResponseParser } from "../parser/ResponseParser";
import { RetrievalEngine } from "../memory/RetrievalEngine";
import { IterationTracker } from "../memory/IterationTracker";
import { Logger } from "../utils/logger";

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
        this.adapters.set("chatgpt", new ChatGPTAdapter(this.browserManager));
        this.adapters.set("gemini", new GeminiAdapter(this.browserManager));
        this.adapters.set("claude", new ClaudeAdapter(this.browserManager));
        this.adapters.set("grok", new GrokAdapter(this.browserManager));
        this.adapters.set("deepseek", new DeepSeekAdapter(this.browserManager));
    }

    setSidebarPostMessage(callback: (message: any) => void) {
        this.sidebarPostMessage = callback;
    }

    async syncSelected() {
        vscode.window.showInformationMessage("Sync initiated from command palette");
    }

    async syncToPlatform(platform: string, files: string[], prompt: string) {
        try {
            const adapter = this.adapters.get(platform);
            if (!adapter) throw new Error(`No adapter for ${platform}`);

            const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();

            // 🔍 Build RAG context
            const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);
            const contextBlock = this.retrievalEngine.formatContextForPrompt(context);

            // Augment the user prompt with context and skills
            const augmentedPrompt = `${contextBlock}\n\n## User Request\n${prompt}\n\nPlease respond with any code changes in unified diff format (diff --git ...) or FILE: blocks.`;

            Logger.info(`Sync to ${platform} with ${files.length} files, context tokens ~${context.tokenEstimate}`);

            await adapter.initialize();
            await adapter.uploadFiles(files);
            await adapter.sendPrompt(augmentedPrompt);
            const response = await adapter.waitForResponse();

            // 📝 Track iteration
            this.iterationTracker.track({
                platform,
                prompt,
                files,
                responseSummary: response.content.substring(0, 200)
            });

            // Send response to sidebar
            if (this.sidebarPostMessage) {
                this.sidebarPostMessage({ type: "response", content: response.content });
            }

            // Also trigger apply command
            vscode.commands.executeCommand("codex-browser-agent.applyResponse", response);
        } catch (error) {
            this.errorHandler.handle(error);
        }
    }

    async applyResponse(responseData: any) {
        const responseText = responseData.content || responseData;
        let parsedChanges = UnifiedDiffParser.parse(responseText);

        if (parsedChanges.length === 0) {
            const fileBlocks = ResponseParser.parseFILEBlocks(responseText);
            parsedChanges = fileBlocks.map(f => ({ filePath: f.path, content: f.content }));
        }

        if (parsedChanges.length === 0) {
            vscode.window.showWarningMessage("No file changes detected in AI response.");
            return;
        }

        // Show diff confirmation if configured
        if (this.config.showDiffBeforeApply) {
            const choice = await vscode.window.showInformationMessage(
                `Apply changes to ${parsedChanges.length} file(s)?`,
                { modal: true },
                "Yes",
                "Show Diff",
                "No"
            );
            if (choice === "Show Diff") {
                // Open a diff view for each file (simplified: show first file diff)
                const first = parsedChanges[0];
                const originalUri = vscode.Uri.file(first.filePath);
                const modifiedUri = vscode.Uri.parse(`untitled:${path.basename(first.filePath)}.modified`);
                await vscode.workspace.fs.writeFile(modifiedUri, Buffer.from(first.content));
                await vscode.commands.executeCommand("vscode.diff", originalUri, modifiedUri, `${first.filePath} (AI Suggested)`);
                return;
            } else if (choice !== "Yes") {
                return;
            }
        }

        // Apply changes
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

        // Parse and run commands
        const commands = ResponseParser.parseCommands(responseText);
        if (commands.length > 0) {
            const run = await vscode.window.showInformationMessage(
                `Run suggested commands?`,
                "Yes",
                "No"
            );
            if (run === "Yes") {
                const terminal = vscode.window.createTerminal("Codex Agent");
                terminal.show();
                commands.forEach(cmd => terminal.sendText(cmd));
            }
        }

        // Update iteration with applied changes
        const recent = this.iterationTracker.getRecent(1);
        if (recent.length > 0) {
            const last = recent[0];
            last.appliedChanges = applied;
            last.commandsRun = commands;
            // Save back
            const memory = new (await import("../memory/MemoryEngine")).MemoryEngine();
            const all = memory.load("iteration-log.json");
            all[all.length - 1] = last;
            memory.save("iteration-log.json", all);
        }

        vscode.window.showInformationMessage(`✅ Applied changes to ${applied.length} file(s).`);
    }

    dispose() {
        this.browserManager.closeAll();
    }
}
EOF

# ------------------------------------------------------------
# 3. Patch SidebarProvider.ts to wire postMessage
# ------------------------------------------------------------
echo "Patching src/sidebar/SidebarProvider.ts..."

cp src/sidebar/SidebarProvider.ts src/sidebar/SidebarProvider.ts.v2.bak

cat > src/sidebar/SidebarProvider.ts << 'EOF'
import * as vscode from "vscode";
import { ContextEngine } from "../context/ContextEngine";
import { SyncEngine } from "../sync/SyncEngine";
import { CommandRunner } from "../commands/CommandRunner";
import { Config } from "../utils/config";

export class SidebarProvider implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _contextEngine: ContextEngine,
        private readonly _syncEngine: SyncEngine,
        private readonly _commandRunner: CommandRunner,
        private readonly _config: Config
    ) {
        // Give SyncEngine a way to post messages to webview
        this._syncEngine.setSidebarPostMessage((message: any) => {
            this._view?.webview.postMessage(message);
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
                case "selectFiles":
                    await this._handleSelectFiles();
                    break;
                case "syncToAI":
                    await this._syncEngine.syncToPlatform(message.platform, message.files, message.prompt);
                    break;
                case "runCommand":
                    await this._commandRunner.run(message.command);
                    break;
                case "getConfig":
                    this._sendConfig();
                    break;
                case "refreshContext":
                    this._sendContextUpdate();
                    break;
                case "applyResponse":
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
            openLabel: "Select for AI context"
        });
        if (uris) {
            const filePaths = uris.map(uri => uri.fsPath);
            this._contextEngine.addSelectedFiles(filePaths);
            this._sendContextUpdate();
        }
    }

    private _sendConfig() {
        this._view?.webview.postMessage({
            type: "config",
            config: {
                maxFilesPerBatch: this._config.maxFilesPerBatch,
                platforms: ["chatgpt", "gemini", "claude", "grok", "deepseek"],
                showDiffBeforeApply: this._config.showDiffBeforeApply
            }
        });
    }

    private _sendContextUpdate() {
        const contextFiles = this._contextEngine.getRelevantFiles();
        this._view?.webview.postMessage({
            type: "contextUpdate",
            files: contextFiles
        });
    }

    private _getHtmlForWebview(webview: vscode.Webview): string {
        const scriptUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this._extensionUri, "src", "webview", "main.js")
        );
        const styleUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this._extensionUri, "src", "webview", "styles.css")
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
        <h2>Codex Browser Agent v3 (Memory)</h2>
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

# ------------------------------------------------------------
# 4. Ensure parser directory exists
# ------------------------------------------------------------
mkdir -p src/parser

# Create UnifiedDiffParser if not present
if [ ! -f src/parser/UnifiedDiffParser.ts ]; then
    cat > src/parser/UnifiedDiffParser.ts << 'EOF'
export interface DiffChange {
    filePath: string;
    content: string;
}

export class UnifiedDiffParser {
    static parse(diff: string): DiffChange[] {
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
fi

# Create ResponseParser if not present
if [ ! -f src/parser/ResponseParser.ts ]; then
    cat > src/parser/ResponseParser.ts << 'EOF'
export interface FileBlock {
    path: string;
    content: string;
}

export class ResponseParser {
    static parseFILEBlocks(text: string): FileBlock[] {
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

    static parseCommands(text: string): string[] {
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
fi

# ------------------------------------------------------------
# 5. Update extension.ts to initialize memory (optional but good)
# ------------------------------------------------------------
echo "Patching src/extension.ts to initialize memory components..."

cp src/extension.ts src/extension.ts.v2.bak

cat > src/extension.ts << 'EOF'
import * as vscode from "vscode";
import { SidebarProvider } from "./sidebar/SidebarProvider";
import { SyncEngine } from "./sync/SyncEngine";
import { CommandRunner } from "./commands/CommandRunner";
import { FileWatcher } from "./context/FileWatcher";
import { ContextEngine } from "./context/ContextEngine";
import { Logger } from "./utils/logger";
import { ErrorHandler } from "./utils/errorHandler";
import { StorageHelper } from "./utils/storage";
import { Config } from "./utils/config";
import { WorkspaceMap } from "./memory/WorkspaceMap";

export function activate(context: vscode.ExtensionContext) {
    Logger.info("Codex Browser Agent v3 (Memory) activated");

    const storage = new StorageHelper(context);
    const config = new Config();
    const errorHandler = new ErrorHandler();
    const contextEngine = new ContextEngine();
    const fileWatcher = new FileWatcher(contextEngine);
    const syncEngine = new SyncEngine(config, errorHandler, storage);
    const commandRunner = new CommandRunner(config, errorHandler);

    // Initialize workspace map on activation
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (workspaceFolder) {
        const wm = new WorkspaceMap();
        const map = wm.generate(workspaceFolder);
        Logger.info(`Workspace map generated with ${map.length} files.`);
    }

    const sidebarProvider = new SidebarProvider(
        context.extensionUri,
        contextEngine,
        syncEngine,
        commandRunner,
        config
    );

    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(
            "codex-browser-agent-sidebar",
            sidebarProvider
        )
    );

    context.subscriptions.push(
        vscode.commands.registerCommand("codex-browser-agent.openSidebar", () => {
            vscode.commands.executeCommand("workbench.view.extension.codex-browser-agent-sidebar");
        }),
        vscode.commands.registerCommand("codex-browser-agent.syncSelected", async () => {
            await syncEngine.syncSelected();
        }),
        vscode.commands.registerCommand("codex-browser-agent.applyResponse", async (responseData: any) => {
            await syncEngine.applyResponse(responseData);
        }),
        vscode.commands.registerCommand("codex-browser-agent.runCommand", async (command: string) => {
            await commandRunner.run(command);
        })
    );

    fileWatcher.start();
    context.subscriptions.push(fileWatcher);
}

export function deactivate() {
    Logger.info("Codex Browser Agent deactivated");
}
EOF

# ------------------------------------------------------------
# 6. Recompile
# ------------------------------------------------------------
echo "Compiling TypeScript..."
npm run compile

echo ""
echo "✅ Upgrade to v3 (Memory + RAG) complete!"
echo ""
echo "New features enabled:"
echo "✔ Iteration memory (tracks every sync)"
echo "✔ Workspace map generation"
echo "✔ Skill loader (place .skill.json files in .codex-memory/skills/)"
echo "✔ Context injection into prompts"
echo "✔ Decision tracking (use .codex-memory/decisions.json)"
echo ""
echo "Next steps:"
echo "1. Restart your extension host (press F5 or reload window)"
echo "2. Optionally add skill JSON files to .codex-memory/skills/"
echo "3. Test a sync — the prompt will now include workspace context and recent iterations"
echo ""
echo "Your backups: src/sync/SyncEngine.ts.v2.bak, src/sidebar/SidebarProvider.ts.v2.bak, src/extension.ts.v2.bak"