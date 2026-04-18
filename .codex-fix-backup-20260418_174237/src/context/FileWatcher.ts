import * as vscode from 'vscode';
import { ContextEngine } from './ContextEngine';

export class FileWatcher implements vscode.Disposable {
    private watcher: vscode.FileSystemWatcher;
    
    constructor(private contextEngine: ContextEngine) {
        this.watcher = vscode.workspace.createFileSystemWatcher('**/*');
        this.watcher.onDidChange(uri => this.handleChange(uri));
        this.watcher.onDidCreate(uri => this.handleChange(uri));
    }
    
    private handleChange(uri: vscode.Uri) {
        const relevant = this.contextEngine.getRelevantFiles();
        if (relevant.includes(uri.fsPath)) {
            // Notify UI to refresh
        }
    }
    
    start() {
        // Already watching via constructor
    }
    
    dispose() {
        this.watcher.dispose();
    }
}
