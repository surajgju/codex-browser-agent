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
