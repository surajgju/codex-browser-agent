import * as vscode from 'vscode';
import { Logger } from './logger';

export class ErrorHandler {
    handle(error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        Logger.error(message);
        vscode.window.showErrorMessage(`Codex Agent Error: ${message}`);
    }
}
