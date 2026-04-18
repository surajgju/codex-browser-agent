# 1. Add imports to SyncEngine.ts (after ResponseParser import)
cd /Users/suraj/development/codex-browser-agent

# Create a backup of SyncEngine.ts
cp src/sync/SyncEngine.ts src/sync/SyncEngine.ts.bak

# Insert the new import lines using ed (more reliable than sed on macOS)
cat << 'EOF' | ed src/sync/SyncEngine.ts
/import { ResponseParser }/
a
import { AgentLoop } from "../agent/AgentLoop";
import { LSPClient } from "../lsp/LSPClient";
import { VectorStore } from "../vector/VectorStore";
.
w
q
EOF

# 2. Add LSP & VectorStore initialization after registerAdapters()
cat << 'EOF' | ed src/sync/SyncEngine.ts
/this.registerAdapters();/
a
        this.lspClient = new LSPClient();
        this.vectorStore = new VectorStore();
        this.lspClient.initialize();
        this.vectorStore.initialize();
.
w
q
EOF

# 3. Replace syncToPlatform method with agent loop version
# We'll use a simple approach: comment out old method and append new one
cat >> src/sync/SyncEngine.ts << 'EOF2'

// NEW autonomous agent loop implementation
async syncToPlatform(platform: string, files: string[], prompt: string) {
    Logger.info(`SyncEngine: Using autonomous agent loop`);
    const adapter = this.adapters.get(platform);
    if (!adapter) throw new Error(`No adapter for ${platform}`);
    const agent = new AgentLoop(adapter, this.lspClient, this.vectorStore);
    await agent.run(prompt);
    return;
}
EOF2

# 4. Append unified diff parser methods to ResponseParser.ts
cat >> src/parser/ResponseParser.ts << 'EOF3'

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
EOF3

# 5. Append ghost text provider to SidebarProvider.ts
cat >> src/SidebarProvider.ts << 'EOF4'

    // Inline ghost text (cursor-like) – simplified version
    private registerGhostTextProvider() {
        vscode.languages.registerHoverProvider('*', {
            provideHover: async (document, position) => {
                // Show AI suggestion on hover (can be extended)
                return new vscode.Hover("💡 Codex: Press Ctrl+I to ask AI");
            }
        });
    }
EOF4

# 6. Add speculative execution command to extension.ts (if not already present)
if ! grep -q "ShadowWorkspace" src/extension.ts; then
    cat >> src/extension.ts << 'EOF5'

    // Production-grade features initialization
    import { ShadowWorkspace } from './speculative/ShadowWorkspace';
    import { ModelRouter } from './orchestrator/ModelRouter';
    import { DiffApplier } from './diff/DiffApplier';

    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();
    const shadow = new ShadowWorkspace(workspaceRoot);
    const diffApplier = new DiffApplier();
    // Register speculative execution command
    vscode.commands.registerCommand('codex-browser-agent.speculativeApply', async () => {
        await shadow.create();
        const diff = await shadow.showDiff();
        const accept = await vscode.window.showInformationMessage('Apply changes?', 'Yes', 'No');
        if (accept === 'Yes') await shadow.accept();
        await shadow.cleanup();
    });
EOF5
fi

# 7. Update package.json commands (if jq is available)
if command -v jq &> /dev/null; then
    jq '.contributes.commands += [
        {"command": "codex-browser-agent.speculativeApply", "title": "Codex: Apply in Shadow Workspace"},
        {"command": "codex-browser-agent.agentLoop", "title": "Codex: Start Autonomous Agent"}
    ]' package.json > package.json.tmp && mv package.json.tmp package.json
else
    echo "⚠️ jq not found. Please manually add these two commands to package.json:"
    echo '  {"command": "codex-browser-agent.speculativeApply", "title": "Codex: Apply in Shadow Workspace"},'
    echo '  {"command": "codex-browser-agent.agentLoop", "title": "Codex: Start Autonomous Agent"}'
fi

echo ""
echo "✅ Manual patching completed."
echo ""
echo "Next steps:"
echo "1. Run 'npm run compile' to build the extension."
echo "2. Reload VS Code (or press F5)."
echo "3. Test the new features."