import * as vscode from 'vscode';

export class Config {
    private get config() {
        return vscode.workspace.getConfiguration('codex-browser-agent');
    }
    
    get maxFilesPerBatch(): number {
        return this.config.get<number>('maxFilesPerBatch', 10);
    }
    
    get maxConcurrentBrowsers(): number {
        return this.config.get<number>('maxConcurrentBrowsers', 5);
    }
    
    get operationTimeout(): number {
        return this.config.get<number>('operationTimeout', 60);
    }
    
    get allowedCommands(): string[] {
        return this.config.get<string[]>('allowedCommands', []);
    }
    
    get autoGitStage(): boolean {
        return this.config.get<boolean>('autoGitStage', false);
    }
    
    get showDiffBeforeApply(): boolean {
        return this.config.get<boolean>('showDiffBeforeApply', true);
    }
    
    get browserPath(): string {
        return this.config.get<string>('browserPath', '');
    }
}
