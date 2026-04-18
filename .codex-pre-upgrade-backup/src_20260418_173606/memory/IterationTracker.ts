import { MemoryEngine } from "./MemoryEngine";

export interface IterationEntry {
    timestamp: string;
    platform: string;
    prompt: string;
    files: string[];
    responseSummary?: string;
    appliedChanges?: { file: string; snippet: string }[];
    commandsRun?: string[];
}

export class IterationTracker {
    private memory: MemoryEngine;

    constructor(workspaceFolder?: string) {
        this.memory = new MemoryEngine(workspaceFolder);
    }

    track(entry: Omit<IterationEntry, "timestamp">): void {
        const record: IterationEntry = {
            ...entry,
            timestamp: new Date().toISOString()
        };
        this.memory.append("iteration-log.json", record);
    }

    getRecent(limit: number = 5): IterationEntry[] {
        const all = this.memory.load("iteration-log.json") as IterationEntry[];
        return all.slice(-limit);
    }
}
