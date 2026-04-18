import { Page } from 'playwright';
import { BrowserManager } from './BrowserManager';

export interface AIResponse {
    content: string;
    suggestedCommands?: string[];
    fileChanges?: { path: string; content: string }[];
}

export abstract class PlatformAdapter {
    protected page!: Page;
    
    constructor(
        protected platformId: string,
        protected browserManager: BrowserManager
    ) {}
    
    async initialize(): Promise<void> {
        this.page = await this.browserManager.getPage(this.platformId);
        await this.ensureLoggedIn();
    }
    
    abstract ensureLoggedIn(): Promise<void>;
    abstract uploadFiles(filePaths: string[]): Promise<void>;
    abstract sendPrompt(prompt: string): Promise<void>;
    abstract waitForResponse(): Promise<AIResponse>;
}
