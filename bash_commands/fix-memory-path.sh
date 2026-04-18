#!/bin/bash
set -e

echo "🔧 Patching MemoryEngine to use safe fallback path..."

# Backup original
cp src/memory/MemoryEngine.ts src/memory/MemoryEngine.ts.bak

cat > src/memory/MemoryEngine.ts << 'EOF'
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

export class MemoryEngine {
    private base: string;

    constructor(workspaceFolder?: string) {
        if (workspaceFolder) {
            this.base = path.join(workspaceFolder, ".codex-memory");
        } else {
            // Try to get workspace folder from VS Code API
            const wsFolders = vscode.workspace.workspaceFolders;
            if (wsFolders && wsFolders.length > 0) {
                this.base = path.join(wsFolders[0].uri.fsPath, ".codex-memory");
            } else {
                // Fallback to extension global storage path (safe, writable)
                // Since we don't have context here, use a temporary directory in user home
                const homeDir = process.env.HOME || process.env.USERPROFILE || "/tmp";
                this.base = path.join(homeDir, ".codex-memory");
                console.warn(`No workspace folder found. Using fallback memory path: ${this.base}`);
            }
        }
        this.ensureDir();
    }

    private ensureDir(): void {
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

# Recompile
npm run compile

echo ""
echo "✅ MemoryEngine patched. Now uses ~/.codex-memory as fallback when no workspace is open."
echo "   Restart the extension host (F5) to apply changes."
