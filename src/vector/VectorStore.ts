import * as fs from 'fs';
import * as path from 'path';
import { Logger } from '../utils/logger';

interface Chunk {
    text: string;
    filePath: string;
    keywords: Set<string>;
}

/**
 * VectorStore – pure TypeScript keyword-based retrieval.
 * Replaces hnswlib-node + @xenova/transformers (native binaries)
 * with a fast TF-IDF-style keyword scoring engine.
 * No native compilation required.
 */
export class VectorStore {
    private chunks: Chunk[] = [];
    private indexedFiles = new Set<string>();

    async initialize(): Promise<void> {
        Logger.info('VectorStore: Initialized (pure TS keyword engine)');
    }

    async indexFile(filePath: string, chunkSize = 100): Promise<void> {
        if (this.indexedFiles.has(filePath)) return;
        try {
            const content = fs.readFileSync(filePath, 'utf-8');
            const lines = content.split('\n');
            for (let i = 0; i < lines.length; i += chunkSize) {
                const chunk = lines.slice(i, i + chunkSize).join('\n');
                this.chunks.push({
                    text: chunk,
                    filePath,
                    keywords: this.extractKeywords(chunk)
                });
            }
            this.indexedFiles.add(filePath);
            Logger.info(`VectorStore: Indexed ${filePath}`);
        } catch (err) {
            Logger.warn(`VectorStore: Could not index ${filePath}: ${err}`);
        }
    }

    async search(query: string, k = 5): Promise<{ text: string; filePath: string; score: number }[]> {
        const queryKw = this.extractKeywords(query);
        const scored = this.chunks.map(chunk => {
            let score = 0;
            for (const kw of queryKw) {
                if (chunk.keywords.has(kw)) score++;
            }
            return { ...chunk, score };
        });

        return scored
            .filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score)
            .slice(0, k)
            .map(r => ({ text: r.text, filePath: r.filePath, score: r.score }));
    }

    private extractKeywords(text: string): Set<string> {
        const stopWords = new Set(['the', 'a', 'is', 'in', 'it', 'of', 'to', 'and', 'for', 'with', 'that', 'this', 'from']);
        const words = text
            .toLowerCase()
            .split(/[\s\W]+/)
            .filter(w => w.length > 2 && !stopWords.has(w));
        return new Set(words);
    }
}
