import { Page } from 'playwright';
import { BrowserManager } from './BrowserManager';
import { Logger } from '../utils/logger';

export interface AIResponse {
    content: string;
    suggestedCommands?: string[];
    fileChanges?: { path: string; content: string }[];
}

export abstract class PlatformAdapter {
    protected page!: Page;
    public initialized = false;
    
    constructor(
        protected platformId: string,
        protected browserManager: BrowserManager
    ) {}
    
    async initialize(): Promise<void> {
        this.page = await this.browserManager.getPage(this.platformId);
        await this.ensureLoggedIn();
        this.initialized = true;
    }

    /**
     * Check if we are already on the expected chat page.
     */
    protected async isOnChatPage(): Promise<boolean> {
        const url = this.page.url();
        // Return true if URL contains the platform's domain and no login parameters
        return url.includes(this.platformId) && !url.includes('login') && !url.includes('signin');
    }

    /**
     * Navigate only if not already on chat page to preserve session history.
     */
    protected async navigateToChatIfNeeded(chatUrl: string): Promise<void> {
        if (await this.isOnChatPage()) {
            Logger.info(`${this.platformId}: Already on chat page, skipping navigation to preserve session.`);
            return;
        }
        Logger.info(`${this.platformId}: Navigating to ${chatUrl}`);
        await this.page.goto(chatUrl, { waitUntil: 'domcontentloaded' });
    }
    
    abstract ensureLoggedIn(): Promise<void>;
    abstract uploadFiles(filePaths: string[]): Promise<void>;
    abstract sendPrompt(prompt: string): Promise<void>;
    abstract waitForResponse(): Promise<AIResponse>;
}
