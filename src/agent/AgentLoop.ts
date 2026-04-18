import * as vscode from 'vscode';
import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
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
    private maxIterations = 5;
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
            const systemPrompt = this.buildSystemPrompt();
            const fullPrompt = `${systemPrompt}\n\n${currentPrompt}`;
            
            await this.adapter.sendPrompt(fullPrompt);
            const response: AIResponse = await this.adapter.waitForResponse();
            const content = response.content;
            
            const { thought, action, actionInput } = this.parseResponse(content);
            Logger.info(`Agent thought: ${thought}`);
            Logger.info(`Agent action: ${action}`);
            
            const observation = await this.toolExecutor.execute(action, actionInput);
            this.steps.push({ thought, action, actionInput, observation });
            
            if (this.isGoalAchieved(observation)) {
                Logger.info("Agent goal achieved");
                break;
            }
            
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
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
            try {
                return JSON.parse(jsonMatch[0]);
            } catch (e) {
                Logger.warn(`Failed to parse JSON: ${e}`);
            }
        }
        return { thought: "Parsing failed", action: "ask_user", actionInput: { question: "Could not parse action, please specify next step" } };
    }

    private isGoalAchieved(observation: string): boolean {
        return observation.includes("GOAL_ACHIEVED");
    }
}
