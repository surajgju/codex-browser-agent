import { Logger } from '../utils/logger';

export interface DiffChange {
    filePath: string;
    content: string;
}

export class UnifiedDiffParser {
    private static cleanResponse(text: string): string {
        const lines = text.split('\n');
        const cleanedLines = lines.filter(line => {
            const trimmed = line.trim();
            if (trimmed.startsWith('diffCopyDownload')) return false;
            if (trimmed === 'Copy') return false;
            if (trimmed === 'Download') return false;
            if (trimmed === '```') return false;
            return true;
        });
        return cleanedLines.join('\n');
    }

    static parse(diff: any): DiffChange[] {
        if (!diff || typeof diff !== 'string') {
            Logger.warn('UnifiedDiffParser received non-string input');
            return [];
        }
        let cleanedDiff = this.cleanResponse(diff);
        const codeBlockMatch = cleanedDiff.match(/```(?:diff)?\s*([\s\S]*?)```/i);
        if (codeBlockMatch) cleanedDiff = codeBlockMatch[1];
        
        const files: DiffChange[] = [];
        const blocks = cleanedDiff.split(/^diff --git /m);
        Logger.info(`UnifiedDiffParser: Found ${blocks.length - 1} diff blocks`);
        
        for (const block of blocks) {
            if (!block.trim()) continue;
            const lines = block.split('\n');
            const fileLine = lines[0];
            const match = fileLine.match(/a\/(.+?)\s+b\/(.+)/);
            if (!match) continue;
            const filePath = match[2].trim();
            const contentLines = lines.filter(l => l.startsWith('+') && !l.startsWith('+++')).map(l => l.slice(1));
            const content = contentLines.join('\n');
            if (content.trim()) {
                files.push({ filePath, content });
                Logger.info(`UnifiedDiffParser: Parsed diff for ${filePath}`);
            }
        }
        return files;
    }
}
