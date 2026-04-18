import * as vscode from 'vscode';
import { PlatformAdapter } from '../browser/PlatformAdapter';
import { ToolExecutor } from './ToolExecutor';
import { LSPClient } from '../lsp/LSPClient';
import { VectorStore } from '../vector/VectorStore';
import { Logger } from '../utils/logger';

export interface AgentStep {
    thought: string;
    action: string;
    actionInput: any;
    observation: string;
}

export class AgentLoop {
    private toolExecutor: ToolExecutor;
    private maxIterations = 10;
    private steps: AgentStep[] = [];

    constructor(
        private adapter: PlatformAdapter,
        private lsp: LSPClient,
        private vectorStore: VectorStore
    ) {
        this.toolExecutor = new ToolExecutor(lsp, vectorStore);
    }

    async run(initialPrompt: string): Promise<void> {
        let currentPrompt = initialPrompt;
        for (let i = 0; i < this.maxIterations; i++) {
            Logger.info(`Agent iteration ${i+1}`);
            // Send prompt + available tools to LLM
            const systemPrompt = this.buildSystemPrompt();
            const response = await this.adapter.sendPromptAndGetResponse(systemPrompt + "\n\n" + currentPrompt);
            const { thought, action, actionInput } = this.parseResponse(response.content);
            
            // Execute tool
            const observation = await this.toolExecutor.execute(action, actionInput);
            this.steps.push({ thought, action, actionInput, observation });
            
            // Check if goal achieved
            if (this.isGoalAchieved(observation)) break;
            
            // Feed observation back to LLM
            currentPrompt = `Observation: ${observation}\n\nContinue with next step.`;
        }
    }

    private buildSystemPrompt(): string {
        return `You are an autonomous coding agent. Available tools:
- read_file(path) -> file content
- list_dir(path) -> directory listing
- search_regex(pattern, path) -> matches
- replace_content(file, old_str, new_str) -> applies change
- run_command(cmd) -> stdout/stderr
- ask_user(question) -> user answer

Respond in JSON format: {"thought": "...", "action": "tool_name", "actionInput": {...}}`;
    }

    private parseResponse(content: string): any {
        // Extract JSON from LLM response (simplified)
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        return jsonMatch ? JSON.parse(jsonMatch[0]) : { thought: "", action: "ask_user", actionInput: { question: "Could not parse action" } };
    }

    private isGoalAchieved(observation: string): boolean {
        return observation.includes("GOAL_ACHIEVED");
    }
}
