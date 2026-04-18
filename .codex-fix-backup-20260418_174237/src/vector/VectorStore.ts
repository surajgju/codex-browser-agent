import { HierarchicalNSW } from 'hnswlib-node';
import * as fs from 'fs';
import * as path from 'path';
import { pipeline } from '@xenova/transformers';

export class VectorStore {
    private index: HierarchicalNSW | null = null;
    private embedder: any;
    private chunks: { text: string; filePath: string }[] = [];

    async initialize(dimension = 384) {
        this.index = new HierarchicalNSW('cosine', dimension);
        this.embedder = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    }

    async indexFile(filePath: string, chunkSize = 500) {
        const content = fs.readFileSync(filePath, 'utf-8');
        const lines = content.split('\n');
        for (let i = 0; i < lines.length; i += chunkSize) {
            const chunk = lines.slice(i, i + chunkSize).join('\n');
            const embedding = await this.embedder(chunk, { pooling: 'mean', normalize: true });
            const id = this.chunks.length;
            this.index!.addPoint(embedding.data, id);
            this.chunks.push({ text: chunk, filePath });
        }
    }

    async search(query: string, k = 5): Promise<{ text: string; filePath: string; score: number }[]> {
        const queryEmbedding = await this.embedder(query, { pooling: 'mean', normalize: true });
        const result = this.index!.searchKnn(queryEmbedding.data, k);
        return result.neighbors.map((id, idx) => ({
            ...this.chunks[id],
            score: result.distances[idx]
        }));
    }
}
