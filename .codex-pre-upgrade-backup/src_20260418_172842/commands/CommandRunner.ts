import * as vscode from 'vscode';
import { Config } from '../utils/config';
import { ErrorHandler } from '../utils/errorHandler';
import { Logger } from '../utils/logger';

export class CommandRunner {
    constructor(private config: Config, private errorHandler: ErrorHandler) {}
    
    async run(command: string): Promise<void> {
        Logger.info(`CommandRunner: Evaluating requested command: ${command}`);
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
        Logger.info(`CommandRunner: Sending command to VS Code terminal -> ${command}`);
        terminal.sendText(command);
    }
}
