import * as vscode from 'vscode';

export class StorageHelper {
    constructor(private context: vscode.ExtensionContext) {}
    
    get<T>(key: string): T | undefined {
        return this.context.globalState.get<T>(key);
    }
    
    async set(key: string, value: any) {
        await this.context.globalState.update(key, value);
    }
}
