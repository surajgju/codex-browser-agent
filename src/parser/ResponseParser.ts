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
                    for (let j = i + 1; j < lines.length; j++) {
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

    static parseBashScript(text: any): string | null {
        if (!text || typeof text !== 'string') {
            Logger.warn('ResponseParser: non-string input');
            return null;
        }

        // Match standard markdown bash block
        const match = text.match(/```bash\s*\n([\s\S]*?)```/);
        if (match) {
            Logger.info(`ResponseParser: Extracted bash script (${match[1].length} chars)`);
            return match[1].trim();
        }

        // Fallback to any generic code block if not explicitly labeled 'bash'
        const fallbackMatch = text.match(/```(?:\w*)\s*\n([\s\S]*?)```/);
        if (fallbackMatch) {
            Logger.info(`ResponseParser: Extracted fallback generic script`);
            return fallbackMatch[1].trim();
        }

        // DOM extraction fallback: Playwright 'textContent' strips backticks.
        // Look for shebang which is a definitive start of the bash script.
        const shebangIndex = text.indexOf('#!/bin/bash');
        if (shebangIndex !== -1) {
            Logger.info(`ResponseParser: Found shebang, extracting raw text`);
            return text.substring(shebangIndex).trim();
        }

        // Extreme fallback: the whole text is probably the script, just strip UI artifacts
        // from ChatGPT/DeepSeek like "bashCopyDownloadcat" -> "cat"
        // We use (?:...)+ to match consecutive squashed artifact words.
        let cleanedText = text.replace(/^(?:bash|copy|download|sh|javascript|html|css|json|typescript|python)+\s*/i, '').trim();
        if (cleanedText) {
            Logger.info(`ResponseParser: Falling back to treating entire cleaned text as bash script`);
            return cleanedText;
        }

        return null;
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

    static parseUnifiedDiff(text: string): string | null {
        if (!text || typeof text !== 'string') return null;
        
        // Standard markdown extraction
        const strictMatch = text.match(/```diff\s*\n([\s\S]*?)```/);
        if (strictMatch) {
            return strictMatch[1].trim();
        }

        // Fallback: If Playwright DOM squashes backticks, look for standard diff headers explicitly
        // Assumes a unified diff starts with '--- ' and '+++ '
        const squashedMatch = text.match(/(--- [^\n]+\n\+\+\+ [^\n]+\n@@[\s\S]*?)(?:\s*END_DIFF|$)/i);
        if (squashedMatch) {
            return squashedMatch[1].trim();
        }

        return null;
    }

    static parseASTPatch(text: string): { targetNode: string; newCode: string } | null {
        if (!text || typeof text !== 'string') return null;

        // Try standard markdown parsing
        const strictMatch = text.match(/AST_PATCH:\s*([^\n]+)\s*\n```[\w]*\s*\n([\s\S]*?)```/i);
        if (strictMatch) {
            return { targetNode: strictMatch[1].trim(), newCode: strictMatch[2].trim() };
        }

        // Fallback: DOM squashed fences. Capture everything after the AST_PATCH node declaration.
        const squashedMatch = text.match(/AST_PATCH:\s*([^\n]+)\s*\n([\s\S]*?)(?:\s*END_PATCH|$)/i);
        if (squashedMatch) {
            return { targetNode: squashedMatch[1].trim(), newCode: squashedMatch[2].trim() };
        }

        return null;
    }
}
