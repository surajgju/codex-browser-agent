import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import { LSPClient } from '../lsp/LSPClient';
import { VectorStore } from '../vector/VectorStore';
import { Logger } from '../utils/logger';

const execAsync = promisify(exec);

export class ToolExecutor {
    constructor(private lsp: LSPClient, private vectorStore: VectorStore) {}

    async execute(toolName: string, input: any): Promise<string> {
        Logger.info(`Executing tool: ${toolName} with input ${JSON.stringify(input)}`);
        switch (toolName) {
            case 'read_file':
                return this.readFile(input.path);
            case 'list_dir':
                return this.listDir(input.path);
            case 'search_regex':
                return this.searchRegex(input.pattern, input.path);
            case 'replace_content':
                return this.replaceContent(input.file, input.old_str, input.new_str);
            case 'run_command':
                return this.runCommand(input.cmd);
            case 'ask_user':
                return this.askUser(input.question);
            default:
                return `Unknown tool: ${toolName}`;
        }
    }

    private async readFile(filePath: string): Promise<string> {
        try {
            return fs.readFileSync(filePath, 'utf-8');
        } catch (err) {
            return `Error reading file: ${err}`;
        }
    }

    private async listDir(dirPath: string): Promise<string> {
        try {
            const files = fs.readdirSync(dirPath);
            return files.join('\n');
        } catch (err) {
            return `Error listing directory: ${err}`;
        }
    }

    private async searchRegex(pattern: string, searchPath: string): Promise<string> {
        // Simplified: use grep if available, else fallback
        try {
            const { stdout } = await execAsync(`grep -rn "${pattern}" "${searchPath}"`);
            return stdout || "No matches found";
        } catch {
            return "Search failed or no matches";
        }
    }

    private async replaceContent(file: string, oldStr: string, newStr: string): Promise<string> {
        try {
            const content = fs.readFileSync(file, 'utf-8');
            const updated = content.replace(new RegExp(oldStr, 'g'), newStr);
            fs.writeFileSync(file, updated, 'utf-8');
            return `Replaced occurrences in ${file}`;
        } catch (err) {
            return `Replace failed: ${err}`;
        }
    }

    private async runCommand(cmd: string): Promise<string> {
        try {
            const { stdout, stderr } = await execAsync(cmd);
            return stdout || stderr || "Command executed (no output)";
        } catch (err: any) {
            return `Command failed: ${err.message}`;
        }
    }

    private async askUser(question: string): Promise<string> {
        const answer = await vscode.window.showInputBox({ prompt: question });
        return answer || "User did not provide an answer";
    }
}
