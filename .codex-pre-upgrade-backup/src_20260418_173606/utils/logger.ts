import * as vscode from 'vscode';

export class Logger {
    private static output = vscode.window.createOutputChannel('Codex Browser Agent');
    
    static info(message: string) {
        this.output.appendLine(`[INFO] ${new Date().toISOString()} - ${message}`);
    }
    
    static warn(message: string) {
        this.output.appendLine(`[WARN] ${new Date().toISOString()} - ${message}`);
    }
    
    static error(message: string) {
        this.output.appendLine(`[ERROR] ${new Date().toISOString()} - ${message}`);
    }
}
