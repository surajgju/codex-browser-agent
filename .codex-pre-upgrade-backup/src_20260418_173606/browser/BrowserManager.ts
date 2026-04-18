import { chromium, BrowserContext, Page } from 'playwright';
import * as vscode from 'vscode';
import * as path from 'path';
import { Logger } from '../utils/logger';
import { Config } from '../utils/config';

export class BrowserManager {
    private static instance: BrowserManager;
    private browsers: Map<string, { context: BrowserContext }> = new Map();
    private storageBasePath: string;
    
    private constructor(private config: Config) {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        this.storageBasePath = workspaceFolder 
            ? path.join(workspaceFolder.uri.fsPath, '.codex-browser-data')
            : path.join(require('os').tmpdir(), 'codex-browser-data');
    }
    
    static getInstance(config: Config): BrowserManager {
        if (!BrowserManager.instance) {
            BrowserManager.instance = new BrowserManager(config);
        }
        return BrowserManager.instance;
    }
    
    async getPage(platform: string): Promise<Page> {
        Logger.info(`BrowserManager: Getting page for ${platform}`);
        if (!this.browsers.has(platform)) {
            await this.launchBrowser(platform);
        }
        const { context } = this.browsers.get(platform)!;
        const pages = context.pages();
        if (pages.length > 0) {
            Logger.info(`BrowserManager: Reusing existing page for ${platform}`);
            return pages[0];
        }
        Logger.info(`BrowserManager: Creating new page for ${platform}`);
        return await context.newPage();
    }
    
    private async launchBrowser(platform: string) {
        const userDataDir = path.join(this.storageBasePath, platform);
        Logger.info(`BrowserManager: Launching browser for ${platform} with user data dir ${userDataDir}`);
        const context = await chromium.launchPersistentContext(userDataDir, {
            headless: false,
            executablePath: this.config.browserPath || undefined,
            ignoreDefaultArgs: ['--enable-automation'],
            args: [
                '--disable-blink-features=AutomationControlled',
                '--disable-infobars',
                '--no-sandbox'
            ]
        });

        // Critical anti-bot stealth injections to bypass Cloudflare
        await context.addInitScript("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})");
        await context.addInitScript("window.navigator.chrome = { runtime: {} };");

        this.browsers.set(platform, { context });
        Logger.info(`BrowserManager: Browser launched for ${platform} with stealth features enabled.`);
    }
    
    async closeAll() {
        Logger.info('BrowserManager: Closing all browsers');
        for (const [platform, { context }] of this.browsers) {
            await context.close();
        }
        this.browsers.clear();
    }
}
