#!/bin/bash
set -e  # exit on error

# ------------------------------------------------------------
# 1. Configuration & safety
# ------------------------------------------------------------
PROJECT_ROOT="$(pwd)"
BACKUP_DIR="$PROJECT_ROOT/.codex-pre-upgrade-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🚀 Codex Browser Agent → Production Grade Upgrade"
echo "Project root: $PROJECT_ROOT"

# Optional backup (comment out to skip)
read -p "Create backup of current source in $BACKUP_DIR? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -r src "$BACKUP_DIR/src_$TIMESTAMP"
    cp package.json "$BACKUP_DIR/package_$TIMESTAMP.json"
    echo "✅ Backup saved to $BACKUP_DIR"
fi

# ------------------------------------------------------------
# 2. Install new dependencies
# ------------------------------------------------------------
echo "📦 Installing required npm packages..."
npm install --save --legacy-peer-deps \
    vscode-languageclient \
    tree-sitter@0.21.1 \
    tree-sitter-typescript@0.20.5 \
    tree-sitter-python@0.23.6 \
    tree-sitter-java@0.23.5 \
    hnswlib-node \
    sqlite3 \
    @xenova/transformers \
    diff \
    temp \
    chokidar

npm install --save-dev --legacy-peer-deps \
    @types/diff \
    @types/temp
echo "📁 Creating module directories..."
mkdir -p src/agent
mkdir -p src/lsp
mkdir -p src/vector
mkdir -p src/diff
mkdir -p src/speculative
mkdir -p src/orchestrator

# ------------------------------------------------------------
# 4. Write new TypeScript files (core modules)
# ------------------------------------------------------------

# 4.1 Agent loop with ReAct and tool calling
cat > src/agent/AgentLoop.ts << 'EOF'
import * as vscode from 'vscode';
import { PlatformAdapter } from '../browser/PlatformAdapter';
import { ToolExecutor } from './ToolExecutor';
import { LSPClient } from '../lsp/LSPClient';
import { VectorStore } from '../vector/VectorStore';
import { Logger } from '../utils/logger';

export interface AgentStep {
    thought: string;
    action: string;
    actionInput: any;
    observation: string;
}

export class AgentLoop {
    private toolExecutor: ToolExecutor;
    private maxIterations = 10;
    private steps: AgentStep[] = [];

    constructor(
        private adapter: PlatformAdapter,
        private lsp: LSPClient,
        private vectorStore: VectorStore
    ) {
        this.toolExecutor = new ToolExecutor(lsp, vectorStore);
    }

    async run(initialPrompt: string): Promise<void> {
        let currentPrompt = initialPrompt;
        for (let i = 0; i < this.maxIterations; i++) {
            Logger.info(`Agent iteration ${i+1}`);
            // Send prompt + available tools to LLM
            const systemPrompt = this.buildSystemPrompt();
            const response = await this.adapter.sendPromptAndGetResponse(systemPrompt + "\n\n" + currentPrompt);
            const { thought, action, actionInput } = this.parseResponse(response.content);
            
            // Execute tool
            const observation = await this.toolExecutor.execute(action, actionInput);
            this.steps.push({ thought, action, actionInput, observation });
            
            // Check if goal achieved
            if (this.isGoalAchieved(observation)) break;
            
            // Feed observation back to LLM
            currentPrompt = `Observation: ${observation}\n\nContinue with next step.`;
        }
    }

    private buildSystemPrompt(): string {
        return `You are an autonomous coding agent. Available tools:
- read_file(path) -> file content
- list_dir(path) -> directory listing
- search_regex(pattern, path) -> matches
- replace_content(file, old_str, new_str) -> applies change
- run_command(cmd) -> stdout/stderr
- ask_user(question) -> user answer

Respond in JSON format: {"thought": "...", "action": "tool_name", "actionInput": {...}}`;
    }

    private parseResponse(content: string): any {
        // Extract JSON from LLM response (simplified)
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        return jsonMatch ? JSON.parse(jsonMatch[0]) : { thought: "", action: "ask_user", actionInput: { question: "Could not parse action" } };
    }

    private isGoalAchieved(observation: string): boolean {
        return observation.includes("GOAL_ACHIEVED");
    }
}
EOF

# 4.2 Tool executor (file ops, search, run commands)
cat > src/agent/ToolExecutor.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import { LSPClient } from '../lsp/LSPClient';
import { VectorStore } from '../vector/VectorStore';
import { Logger } from '../utils/logger';

const execAsync = promisify(exec);

export class ToolExecutor {
    constructor(private lsp: LSPClient, private vectorStore: VectorStore) {}

    async execute(toolName: string, input: any): Promise<string> {
        Logger.info(`Executing tool: ${toolName} with input ${JSON.stringify(input)}`);
        switch (toolName) {
            case 'read_file':
                return this.readFile(input.path);
            case 'list_dir':
                return this.listDir(input.path);
            case 'search_regex':
                return this.searchRegex(input.pattern, input.path);
            case 'replace_content':
                return this.replaceContent(input.file, input.old_str, input.new_str);
            case 'run_command':
                return this.runCommand(input.cmd);
            case 'ask_user':
                return this.askUser(input.question);
            default:
                return `Unknown tool: ${toolName}`;
        }
    }

    private async readFile(filePath: string): Promise<string> {
        try {
            return fs.readFileSync(filePath, 'utf-8');
        } catch (err) {
            return `Error reading file: ${err}`;
        }
    }

    private async listDir(dirPath: string): Promise<string> {
        try {
            const files = fs.readdirSync(dirPath);
            return files.join('\n');
        } catch (err) {
            return `Error listing directory: ${err}`;
        }
    }

    private async searchRegex(pattern: string, searchPath: string): Promise<string> {
        // Simplified: use grep if available, else fallback
        try {
            const { stdout } = await execAsync(`grep -rn "${pattern}" "${searchPath}"`);
            return stdout || "No matches found";
        } catch {
            return "Search failed or no matches";
        }
    }

    private async replaceContent(file: string, oldStr: string, newStr: string): Promise<string> {
        try {
            const content = fs.readFileSync(file, 'utf-8');
            const updated = content.replace(new RegExp(oldStr, 'g'), newStr);
            fs.writeFileSync(file, updated, 'utf-8');
            return `Replaced occurrences in ${file}`;
        } catch (err) {
            return `Replace failed: ${err}`;
        }
    }

    private async runCommand(cmd: string): Promise<string> {
        try {
            const { stdout, stderr } = await execAsync(cmd);
            return stdout || stderr || "Command executed (no output)";
        } catch (err: any) {
            return `Command failed: ${err.message}`;
        }
    }

    private async askUser(question: string): Promise<string> {
        const answer = await vscode.window.showInputBox({ prompt: question });
        return answer || "User did not provide an answer";
    }
}
EOF

# 4.3 LSP Client (symbols, definitions, hover)
cat > src/lsp/LSPClient.ts << 'EOF'
import * as vscode from 'vscode';
import { Logger } from '../utils/logger';

export class LSPClient {
    private client: vscode.LanguageClient | null = null;

    async initialize(): Promise<void> {
        // For simplicity, we use VS Code's built-in LSP via commands
        // In a real implementation, you would create a LanguageClient for each language
        Logger.info("LSP Client initialized (using VS Code native LSP)");
    }

    async getDefinitionAtPosition(uri: string, line: number, character: number): Promise<vscode.Location[]> {
        const doc = await vscode.workspace.openTextDocument(uri);
        const position = new vscode.Position(line, character);
        return await vscode.commands.executeCommand<vscode.Location[]>(
            'vscode.executeDefinitionProvider', doc.uri, position
        ) || [];
    }

    async getSymbols(uri: string): Promise<vscode.DocumentSymbol[]> {
        const doc = await vscode.workspace.openTextDocument(uri);
        return await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
            'vscode.executeDocumentSymbolProvider', doc.uri
        ) || [];
    }

    async getHover(uri: string, line: number, character: number): Promise<string> {
        const doc = await vscode.workspace.openTextDocument(uri);
        const position = new vscode.Position(line, character);
        const hover = await vscode.commands.executeCommand<vscode.Hover>(
            'vscode.executeHoverProvider', doc.uri, position
        );
        return hover?.contents.map(c => c.toString()).join('\n') || '';
    }
}
EOF

# 4.4 Vector Store (RAG using HNSW)
cat > src/vector/VectorStore.ts << 'EOF'
import { HierarchicalNSW } from 'hnswlib-node';
import * as fs from 'fs';
import * as path from 'path';
import { pipeline } from '@xenova/transformers';

export class VectorStore {
    private index: HierarchicalNSW | null = null;
    private embedder: any;
    private chunks: { text: string; filePath: string }[] = [];

    async initialize(dimension = 384) {
        this.index = new HierarchicalNSW('cosine', dimension);
        this.embedder = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    }

    async indexFile(filePath: string, chunkSize = 500) {
        const content = fs.readFileSync(filePath, 'utf-8');
        const lines = content.split('\n');
        for (let i = 0; i < lines.length; i += chunkSize) {
            const chunk = lines.slice(i, i + chunkSize).join('\n');
            const embedding = await this.embedder(chunk, { pooling: 'mean', normalize: true });
            const id = this.chunks.length;
            this.index!.addPoint(embedding.data, id);
            this.chunks.push({ text: chunk, filePath });
        }
    }

    async search(query: string, k = 5): Promise<{ text: string; filePath: string; score: number }[]> {
        const queryEmbedding = await this.embedder(query, { pooling: 'mean', normalize: true });
        const result = this.index!.searchKnn(queryEmbedding.data, k);
        return result.neighbors.map((id, idx) => ({
            ...this.chunks[id],
            score: result.distances[idx]
        }));
    }
}
EOF

# 4.5 Unified Diff + AST Patching
cat > src/diff/DiffApplier.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import * as diff from 'diff';
import Parser from 'tree-sitter';
import TypeScript from 'tree-sitter-typescript';
import { Logger } from '../utils/logger';

export class DiffApplier {
    private parser: Parser;

    constructor() {
        this.parser = new Parser();
        this.parser.setLanguage(TypeScript.typescript);
    }

    applyUnifiedDiff(filePath: string, unifiedDiff: string): boolean {
        try {
            const original = fs.readFileSync(filePath, 'utf-8');
            const patches = diff.parsePatch(unifiedDiff);
            const applied = diff.applyPatch(original, patches[0]);
            if (typeof applied === 'string') {
                fs.writeFileSync(filePath, applied, 'utf-8');
                Logger.info(`Applied unified diff to ${filePath}`);
                return true;
            }
            return false;
        } catch (err) {
            Logger.error(`Diff application failed: ${err}`);
            return false;
        }
    }

    applyASTPatch(filePath: string, targetNode: string, newCode: string): boolean {
        const code = fs.readFileSync(filePath, 'utf-8');
        const tree = this.parser.parse(code);
        // Find node by pattern (simplified – real implementation would traverse)
        const rootNode = tree.rootNode;
        let start = -1, end = -1;
        // Naive search for function/class declaration (example)
        const regex = new RegExp(`(function|class)\\s+${targetNode}\\b[\\s\\S]*?\\n\\}`);
        const match = code.match(regex);
        if (match && match.index !== undefined) {
            start = match.index;
            end = start + match[0].length;
            const newContent = code.slice(0, start) + newCode + code.slice(end);
            fs.writeFileSync(filePath, newContent, 'utf-8');
            Logger.info(`AST patch applied to ${filePath} (replaced ${targetNode})`);
            return true;
        }
        return false;
    }
}
EOF

# 4.6 Speculative Execution & Shadow Workspace
cat > src/speculative/ShadowWorkspace.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';
import { exec } from 'child_process';
import { promisify } from 'util';
import { Logger } from '../utils/logger';

const execAsync = promisify(exec);

export class ShadowWorkspace {
    private shadowRoot: string;
    private originalRoot: string;

    constructor(originalRoot: string) {
        this.originalRoot = originalRoot;
        this.shadowRoot = path.join(os.tmpdir(), `codex-shadow-${crypto.randomBytes(8).toString('hex')}`);
    }

    async create(): Promise<void> {
        await execAsync(`cp -r "${this.originalRoot}" "${this.shadowRoot}"`);
        Logger.info(`Shadow workspace created at ${this.shadowRoot}`);
    }

    async runScript(scriptPath: string): Promise<{ stdout: string; stderr: string; success: boolean }> {
        try {
            const { stdout, stderr } = await execAsync(`bash "${scriptPath}"`, { cwd: this.shadowRoot });
            return { stdout, stderr, success: true };
        } catch (err: any) {
            return { stdout: err.stdout, stderr: err.stderr, success: false };
        }
    }

    async showDiff(): Promise<string> {
        const { stdout } = await execAsync(`diff -urN "${this.originalRoot}" "${this.shadowRoot}" || true`);
        return stdout;
    }

    async accept(): Promise<void> {
        await execAsync(`rsync -a "${this.shadowRoot}/" "${this.originalRoot}/"`);
        Logger.info("Changes accepted from shadow workspace");
    }

    async cleanup(): Promise<void> {
        await execAsync(`rm -rf "${this.shadowRoot}"`);
    }
}
EOF

# 4.7 Multi-model orchestrator (fast router + heavy coder)
cat > src/orchestrator/ModelRouter.ts << 'EOF'
import { PlatformAdapter } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ModelRouter {
    constructor(
        private fastAdapter: PlatformAdapter,   // e.g., Gemini Flash
        private heavyAdapter: PlatformAdapter    // e.g., DeepSeek Coder
    ) {}

    async route(prompt: string, context: string): Promise<string> {
        // Determine complexity: if prompt contains "refactor", "architecture", "large" → heavy
        const isComplex = /refactor|architecture|large|many files|optimize/i.test(prompt);
        const adapter = isComplex ? this.heavyAdapter : this.fastAdapter;
        Logger.info(`Routing to ${isComplex ? 'heavy' : 'fast'} model`);
        await adapter.initialize();
        await adapter.sendPrompt(prompt + "\n\nContext:\n" + context);
        const response = await adapter.waitForResponse();
        return response.content;
    }
}
EOF

# ------------------------------------------------------------
# 5. Patch existing files
# ------------------------------------------------------------

# 5.1 Modify SyncEngine.ts to use AgentLoop
sed -i.bak '/import { ResponseParser }/a import { AgentLoop } from "..\/agent\/AgentLoop";\
import { LSPClient } from "..\/lsp\/LSPClient";\
import { VectorStore } from "..\/vector\/VectorStore";' src/sync/SyncEngine.ts

sed -i.bak '/this.registerAdapters();/a \
        this.lspClient = new LSPClient();\
        this.vectorStore = new VectorStore();\
        this.lspClient.initialize();\
        this.vectorStore.initialize();' src/sync/SyncEngine.ts

# Replace syncToPlatform method to use agent loop
perl -i -0pe 's/async syncToPlatform\([^)]*\) \{.*?\/\/ Send prompt to adapter/syncToPlatform(platform: string, files: string[], prompt: string) {\n        Logger.info(`SyncEngine: Using autonomous agent loop`);\n        const adapter = this.adapters.get(platform);\n        if (!adapter) throw new Error(`No adapter for ${platform}`);\n        const agent = new AgentLoop(adapter, this.lspClient, this.vectorStore);\n        await agent.run(prompt);\n        return;\n        \/\/ Original code below (commented)\n        /s' src/sync/SyncEngine.ts

# 5.2 Update ResponseParser.ts to support unified diff and AST patches
cat >> src/parser/ResponseParser.ts << 'EOF'

    static parseUnifiedDiff(text: string): string | null {
        const match = text.match(/```diff\n([\s\S]*?)```/);
        return match ? match[1] : null;
    }

    static parseASTPatch(text: string): { targetNode: string; newCode: string } | null {
        const match = text.match(/AST_PATCH:\s*([^\n]+)\n```[\s\S]*?\n([\s\S]*?)```/);
        if (match) {
            return { targetNode: match[1].trim(), newCode: match[2] };
        }
        return null;
    }
EOF

# 5.3 Add inline ghost text provider to SidebarProvider.ts
cat >> src/SidebarProvider.ts << 'EOF'

    // Inline ghost text (cursor-like) – simplified version
    private registerGhostTextProvider() {
        vscode.languages.registerHoverProvider('*', {
            provideHover: async (document, position) => {
                // Show AI suggestion on hover (can be extended)
                return new vscode.Hover("💡 Codex: Press Ctrl+I to ask AI");
            }
        });
    }
EOF

# 5.4 Update extension.ts to initialize new components
if ! grep -q "ShadowWorkspace" src/extension.ts; then
    cat >> src/extension.ts << 'EOF'

    // Production-grade features initialization
    import { ShadowWorkspace } from './speculative/ShadowWorkspace';
    import { ModelRouter } from './orchestrator/ModelRouter';
    import { DiffApplier } from './diff/DiffApplier';

    const shadow = new ShadowWorkspace(workspaceRoot);
    const diffApplier = new DiffApplier();
    // Register speculative execution command
    vscode.commands.registerCommand('codex-browser-agent.speculativeApply', async () => {
        await shadow.create();
        // run script in shadow, then show diff
        const diff = await shadow.showDiff();
        const accept = await vscode.window.showInformationMessage('Apply changes?', 'Yes', 'No');
        if (accept === 'Yes') await shadow.accept();
        await shadow.cleanup();
    });
EOF
fi

# 5.5 Add new commands to package.json
if ! grep -q "codex-browser-agent.speculativeApply" package.json; then
    # Use jq if available, else sed
    if command -v jq &> /dev/null; then
        jq '.contributes.commands += [
            {"command": "codex-browser-agent.speculativeApply", "title": "Codex: Apply in Shadow Workspace"},
            {"command": "codex-browser-agent.agentLoop", "title": "Codex: Start Autonomous Agent"}
        ]' package.json > package.json.tmp && mv package.json.tmp package.json
    else
        echo "⚠️ jq not found; please manually add commands to package.json"
    fi
fi

# ------------------------------------------------------------
# 6. Final instructions
# ------------------------------------------------------------
echo ""
echo "✅ Upgrade script completed!"
echo ""
echo "Next steps:"
echo "1. Run 'npm run compile' to build the extension."
echo "2. Reload VS Code (or press F5 to launch debug instance)."
echo "3. Test new features:"
echo "   - Open sidebar, select files, click 'Sync & Get Response' – now uses autonomous agent loop."
echo "   - Run command 'Codex: Start Autonomous Agent' from command palette."
echo "   - Use 'Codex: Apply in Shadow Workspace' to test speculative execution."
echo "4. For LSP and vector indexing, ensure your workspace has a valid language server (e.g., TypeScript, Python)."
echo "5. To index your codebase for RAG, call vectorStore.indexFile() on each file (can be automated)."
echo ""
echo "Refer to the generated modules in src/agent, src/lsp, src/vector, src/diff, src/speculative, src/orchestrator for customization."