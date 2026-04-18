import { MemoryEngine } from "./MemoryEngine";
import { SkillLoader, Skill } from "./SkillLoader";
import { WorkspaceMap } from "./WorkspaceMap";
import { IterationTracker, IterationEntry } from "./IterationTracker";

export interface AugmentedContext {
    recentIterations: IterationEntry[];
    relevantSkills: Skill[];
    workspaceTree: string;
    decisions: any[];
    tokenEstimate: number;
}

export class RetrievalEngine {
    private memory: MemoryEngine;
    private skillLoader: SkillLoader;
    private workspaceMap: WorkspaceMap;
    private iterationTracker: IterationTracker;

    constructor(workspaceFolder?: string) {
        this.memory = new MemoryEngine(workspaceFolder);
        this.skillLoader = new SkillLoader(workspaceFolder);
        this.workspaceMap = new WorkspaceMap();
        this.iterationTracker = new IterationTracker(workspaceFolder);
    }

    buildContext(prompt: string, workspaceRoot: string): AugmentedContext {
        const recentIterations = this.iterationTracker.getRecent(3);
        const relevantSkills = this.skillLoader.findRelevantSkills(prompt);
        const workspaceTree = this.workspaceMap.getFileTree(workspaceRoot, 3);
        const decisions = this.memory.load("decisions.json") as any[];

        // Rough token estimate (4 chars ~ 1 token)
        const contextString = JSON.stringify({ recentIterations, relevantSkills, workspaceTree, decisions });
        const tokenEstimate = Math.ceil(contextString.length / 4);

        return {
            recentIterations,
            relevantSkills,
            workspaceTree,
            decisions: Array.isArray(decisions) ? decisions : [],
            tokenEstimate
        };
    }

    formatContextForPrompt(context: AugmentedContext, maxTokens: number = 2000): string {
        let parts: string[] = [];

        if (context.workspaceTree) {
            parts.push("## Project Structure\n```\n" + context.workspaceTree + "\n```");
        }

        if (context.recentIterations.length > 0) {
            parts.push("## Recent Iterations\n" + context.recentIterations.map(i =>
                `- [${i.timestamp}] ${i.platform}: ${i.prompt.substring(0, 100)}...`
            ).join("\n"));
        }

        if (context.relevantSkills.length > 0) {
            parts.push("## Available Skills\n" + context.relevantSkills.map(s =>
                `- ${s.name}: ${s.description}`
            ).join("\n"));
        }

        let combined = parts.join("\n\n");
        // Truncate if exceeds approximate token limit
        if (combined.length > maxTokens * 4) {
            combined = combined.substring(0, maxTokens * 4) + "\n... (context truncated)";
        }
        return combined;
    }
}
