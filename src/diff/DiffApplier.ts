import * as fs from 'fs';
import * as diff from 'diff';
import { Logger } from '../utils/logger';

/**
 * DiffApplier – pure TypeScript, no native bindings.
 * AST patching is now done via robust regex patterns instead of tree-sitter.
 */
export class DiffApplier {

    applyUnifiedDiff(filePath: string, unifiedDiff: string): boolean {
        try {
            const original = fs.readFileSync(filePath, 'utf-8');
            const patches = diff.parsePatch(unifiedDiff);
            if (!patches || patches.length === 0) {
                Logger.warn(`DiffApplier: No patches found in diff string`);
                return false;
            }
            const applied = diff.applyPatch(original, patches[0]);
            if (typeof applied === 'string') {
                fs.writeFileSync(filePath, applied, 'utf-8');
                Logger.info(`DiffApplier: Applied unified diff to ${filePath}`);
                return true;
            }
            Logger.warn(`DiffApplier: Patch did not apply cleanly to ${filePath}`);
            return false;
        } catch (err) {
            Logger.error(`DiffApplier: Diff application failed: ${err}`);
            return false;
        }
    }

    /**
     * Pure-regex AST-style patch: finds a named function or class declaration
     * and replaces it with the new code block. No native tree-sitter required.
     */
    applyASTPatch(filePath: string, targetNode: string, newCode: string): boolean {
        try {
            const code = fs.readFileSync(filePath, 'utf-8');

            // Match: function name(...) { ... } or class name { ... }
            // Supports async functions, arrow functions assigned to const/let/var
            const patterns = [
                // function declaration: function foo(...) { ... }
                new RegExp(`(export\\s+)?(async\\s+)?function\\s+${targetNode}\\s*\\([\\s\\S]*?\\}`, ''),
                // class declaration: class Foo { ... }
                new RegExp(`(export\\s+)?(abstract\\s+)?class\\s+${targetNode}[\\s\\S]*?^\\}`, 'm'),
                // const/let/var arrow: const foo = (...) => { ... }
                new RegExp(`(export\\s+)?(const|let|var)\\s+${targetNode}\\s*=\\s*[\\s\\S]*?\\};?`, ''),
            ];

            for (const regex of patterns) {
                const match = code.match(regex);
                if (match && match.index !== undefined) {
                    const newContent = code.slice(0, match.index) + newCode + code.slice(match.index + match[0].length);
                    fs.writeFileSync(filePath, newContent, 'utf-8');
                    Logger.info(`DiffApplier: Regex AST patch applied to ${filePath} (replaced '${targetNode}')`);
                    return true;
                }
            }

            Logger.warn(`DiffApplier: Could not find target node '${targetNode}' in ${filePath}`);
            return false;
        } catch (err) {
            Logger.error(`DiffApplier: AST patch failed: ${err}`);
            return false;
        }
    }
}
