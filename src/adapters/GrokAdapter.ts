import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';

export class GrokAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('grok', browserManager); }
    async ensureLoggedIn(): Promise<void> {
        await this.page.goto('https://grok.x.ai');
        await this.page.waitForSelector('textarea', { timeout: 0 });
    }
    async uploadFiles(filePaths: string[]): Promise<void> {
        const content = filePaths.map(p => `${p}:\n${require('fs').readFileSync(p, 'utf8')}`).join('\n');
        const textarea = await this.page.$('textarea');
        await textarea?.fill(content);
    }
    async sendPrompt(prompt: string): Promise<void> {
        const textarea = await this.page.$('textarea');
        await textarea?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }
    async waitForResponse(): Promise<AIResponse> {
        await this.page.waitForSelector('.message-content', { timeout: 60000 });
        const content = await this.page.$eval('.message-content', el => el.textContent) || '';
        return { content };
    }
}
