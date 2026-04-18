import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';

export class ClaudeAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('claude', browserManager); }
    async ensureLoggedIn(): Promise<void> {
        await this.page.goto('https://claude.ai');
        await this.page.waitForSelector('[contenteditable="true"]', { timeout: 0 });
    }
    async uploadFiles(filePaths: string[]): Promise<void> {
        // Claude supports file attachments via paperclip
        const attachBtn = await this.page.$('button[aria-label="Attach files"]');
        if (attachBtn) {
            await attachBtn.click();
            const fileInput = await this.page.$('input[type="file"]');
            await fileInput?.setInputFiles(filePaths);
        }
    }
    async sendPrompt(prompt: string): Promise<void> {
        const editor = await this.page.$('[contenteditable="true"]');
        await editor?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }
    async waitForResponse(): Promise<AIResponse> {
        await this.page.waitForSelector('.prose', { timeout: 60000 });
        const content = await this.page.$eval('.prose', el => el.textContent) || '';
        return { content };
    }
}
