import * as vscode from 'vscode';
import { Config } from '../utils/config';
import { ErrorHandler } from '../utils/errorHandler';

export class CommandRunner {
    constructor(private config: Config, private errorHandler: ErrorHandler) {}
    
    async run(command: string): Promise<void> {
        const allowed = this.config.allowedCommands;
        if (allowed.length > 0 && !allowed.includes(command)) {
            const confirm = await vscode.window.showWarningMessage(
                `Command "${command}" is not in whitelist. Run anyway?`,
                'Yes', 'No'
            );
            if (confirm !== 'Yes') return;
        } else {
            const confirm = await vscode.window.showInformationMessage(
                `Run command: ${command}?`,
                'Yes', 'No'
            );
            if (confirm !== 'Yes') return;
        }
        
        const terminal = vscode.window.createTerminal('Codex Agent');
        terminal.show();
        terminal.sendText(command);
    }
}
