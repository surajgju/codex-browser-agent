import * as fs from 'fs';
import * as path from 'path';
import * as diff from 'diff';
import Parser from 'tree-sitter';
// @ts-ignore
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
