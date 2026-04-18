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
}
