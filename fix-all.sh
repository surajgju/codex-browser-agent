#!/bin/bash
set -e

PROJECT_ROOT="$(pwd)"
echo "🔧 Applying comprehensive fixes to Codex Browser Agent..."

# Backup current state
BACKUP_DIR="$PROJECT_ROOT/.codex-fix-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r src "$BACKUP_DIR"
echo "✅ Backup saved to $BACKUP_DIR"

# ----------------------------------------------------------------------
# 1. Fix SyncEngine.ts: replace syncToPlatform and remove duplicate
# ----------------------------------------------------------------------
SYNC_FILE="src/sync/SyncEngine.ts"
if [ -f "$SYNC_FILE" ]; then
    cp "$SYNC_FILE" "$SYNC_FILE.bak"
    
    # Remove the duplicate method at the end (everything after "// NEW autonomous agent loop implementation")
    sed -i.bak '/^\/\/ NEW autonomous agent loop implementation$/,$d' "$SYNC_FILE"
    
    # Now replace the original syncToPlatform method inside the class
    # We'll use a more reliable approach: extract class body and replace method via Perl
    perl -i -0pe 's/async syncToPlatform\([^)]*\) \{[^}]*\n        Logger\.info\(`SyncEngine: Starting sync.*?(\n        this\.iterationTracker\.track\(.*?\);\n        )/async syncToPlatform(platform: string, files: string[], prompt: string) {\n        Logger.info(`SyncEngine: Using autonomous agent loop`);\n        const adapter = this.adapters.get(platform);\n        if (!adapter) throw new Error(`No adapter for ${platform}`);\n        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();\n        const context = this.retrievalEngine.buildContext(prompt, workspaceRoot);\n        const contextBlock = this.retrievalEngine.formatContextForPrompt(context);\n        const augmentedPrompt = `${contextBlock}\\n\\n## User Request\\n${prompt}`;\n        await adapter.initialize();\n        const agent = new AgentLoop(adapter, this.lspClient, this.vectorStore);\n        await agent.run(augmentedPrompt);\n        if (this.sidebarPostMessage) {\n            this.sidebarPostMessage({ type: "response", content: "[Agent loop completed]" });\n        }\n        this.iterationTracker.track({ platform, prompt, files, responseSummary: "Agent loop execution" });\n        /s' "$SYNC_FILE"
    
    echo "✅ Fixed $SYNC_FILE"
else
    echo "⚠️ $SYNC_FILE not found – skipping"
fi

# ----------------------------------------------------------------------
# 2. Fix AgentLoop.ts: use sendPrompt + waitForResponse
# ----------------------------------------------------------------------
AGENT_LOOP="src/agent/AgentLoop.ts"
if [ -f "$AGENT_LOOP" ]; then
    cat > "$AGENT_LOOP" << 'EOF'
import * as vscode from 'vscode';
import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
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
    private maxIterations = 5;
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
            const systemPrompt = this.buildSystemPrompt();
            const fullPrompt = `${systemPrompt}\n\n${currentPrompt}`;
            
            await this.adapter.sendPrompt(fullPrompt);
            const response: AIResponse = await this.adapter.waitForResponse();
            const content = response.content;
            
            const { thought, action, actionInput } = this.parseResponse(content);
            Logger.info(`Agent thought: ${thought}`);
            Logger.info(`Agent action: ${action}`);
            
            const observation = await this.toolExecutor.execute(action, actionInput);
            this.steps.push({ thought, action, actionInput, observation });
            
            if (this.isGoalAchieved(observation)) {
                Logger.info("Agent goal achieved");
                break;
            }
            
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
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
            try {
                return JSON.parse(jsonMatch[0]);
            } catch (e) {
                Logger.warn(`Failed to parse JSON: ${e}`);
            }
        }
        return { thought: "Parsing failed", action: "ask_user", actionInput: { question: "Could not parse action, please specify next step" } };
    }

    private isGoalAchieved(observation: string): boolean {
        return observation.includes("GOAL_ACHIEVED");
    }
}
EOF
    echo "✅ Fixed $AGENT_LOOP"
else
    echo "⚠️ $AGENT_LOOP not found – skipping"
fi

# ----------------------------------------------------------------------
# 3. Fix ToolExecutor.ts: add vscode import and missing dependencies
# ----------------------------------------------------------------------
TOOL_EXEC="src/agent/ToolExecutor.ts"
if [ -f "$TOOL_EXEC" ]; then
    # Add vscode import at top if missing
    if ! grep -q "import \* as vscode" "$TOOL_EXEC"; then
        sed -i.bak '1i import * as vscode from "vscode";\n' "$TOOL_EXEC"
    fi
    echo "✅ Fixed $TOOL_EXEC"
fi

# ----------------------------------------------------------------------
# 4. Fix VectorStore.ts: handle missing native module gracefully
# ----------------------------------------------------------------------
VECTOR_STORE="src/vector/VectorStore.ts"
if [ -f "$VECTOR_STORE" ]; then
    cat > "$VECTOR_STORE" << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { Logger } from '../utils/logger';

// Simplified vector store – avoids native module issues
export class VectorStore {
    private chunks: { text: string; filePath: string }[] = [];

    async initialize() {
        Logger.info("VectorStore initialized (simplified mode)");
    }

    async indexFile(filePath: string, chunkSize = 500) {
        try {
            const content = fs.readFileSync(filePath, 'utf-8');
            const lines = content.split('\n');
            for (let i = 0; i < lines.length; i += chunkSize) {
                const chunk = lines.slice(i, i + chunkSize).join('\n');
                this.chunks.push({ text: chunk, filePath });
            }
            Logger.info(`Indexed ${filePath} (${this.chunks.length} chunks total)`);
        } catch (err) {
            Logger.warn(`Failed to index ${filePath}: ${err}`);
        }
    }

    async search(query: string, k = 5): Promise<{ text: string; filePath: string; score: number }[]> {
        // Simple keyword search fallback
        const results = this.chunks
            .map(chunk => ({ ...chunk, score: chunk.text.toLowerCase().includes(query.toLowerCase()) ? 1 : 0 }))
            .filter(r => r.score > 0)
            .slice(0, k);
        return results;
    }
}
EOF
    echo "✅ Fixed $VECTOR_STORE (simplified, no native deps)"
fi

# ----------------------------------------------------------------------
# 5. Add dispose method to LSPClient if missing
# ----------------------------------------------------------------------
LSP_CLIENT="src/lsp/LSPClient.ts"
if [ -f "$LSP_CLIENT" ]; then
    if ! grep -q "dispose" "$LSP_CLIENT"; then
        cat >> "$LSP_CLIENT" << 'EOF'

    dispose() {
        // Cleanup if needed
        Logger.info("LSPClient disposed");
    }
EOF
    fi
    echo "✅ Fixed $LSP_CLIENT"
fi

# ----------------------------------------------------------------------
# 6. Append missing parser methods to ResponseParser.ts (if not present)
# ----------------------------------------------------------------------
RESP_PARSER="src/parser/ResponseParser.ts"
if [ -f "$RESP_PARSER" ]; then
    if ! grep -q "parseUnifiedDiff" "$RESP_PARSER"; then
        cat >> "$RESP_PARSER" << 'EOF'

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
        echo "✅ Appended methods to $RESP_PARSER"
    else
        echo "✅ $RESP_PARSER already has methods"
    fi
fi

# ----------------------------------------------------------------------
# 7. Ensure all new modules have vscode import where needed
# ----------------------------------------------------------------------
# ShadowWorkspace.ts
if [ -f "src/speculative/ShadowWorkspace.ts" ] && ! grep -q "import \* as vscode" "src/speculative/ShadowWorkspace.ts"; then
    sed -i.bak '1i import * as vscode from "vscode";\n' "src/speculative/ShadowWorkspace.ts"
fi

# DiffApplier.ts
if [ -f "src/diff/DiffApplier.ts" ] && ! grep -q "import \* as vscode" "src/diff/DiffApplier.ts"; then
    sed -i.bak '1i import * as vscode from "vscode";\n' "src/diff/DiffApplier.ts"
fi

# ModelRouter.ts
if [ -f "src/orchestrator/ModelRouter.ts" ] && ! grep -q "import \* as vscode" "src/orchestrator/ModelRouter.ts"; then
    sed -i.bak '1i import * as vscode from "vscode";\n' "src/orchestrator/ModelRouter.ts"
fi

# ----------------------------------------------------------------------
# 8. Compile the extension
# ----------------------------------------------------------------------
echo "🔨 Compiling extension..."
if npm run compile; then
    echo "✅ Compilation successful!"
    echo ""
    echo "🎉 All fixes applied. Next steps:"
    echo "  1. Reload VS Code (or press F5 to debug)."
    echo "  2. Open sidebar, select files, and test the autonomous agent loop."
    echo "  3. If you see runtime errors, check the output channel 'Codex Browser Agent'."
else
    echo "❌ Compilation failed. Please check the errors above."
    echo "   Restore from backup: cp -r $BACKUP_DIR/src ."
    exit 1
fi