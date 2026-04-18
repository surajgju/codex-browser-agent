import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class GeminiAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('gemini', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        try {
            await this.page.goto('https://gemini.google.com', { waitUntil: 'domcontentloaded' });
            await this.page.waitForSelector('textarea, [contenteditable="true"], .input-area', { timeout: 10000 });
            Logger.info('Gemini: Logged in.');
        } catch (e) {
            Logger.error(`Gemini login failed: ${e}`);
            throw e;
        }
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`Gemini: Uploading ${filePaths.length} files.`);
        const fs = require('fs');
        const content = filePaths.map(p => `FILE: ${p}\n\`\`\`\n${fs.readFileSync(p, 'utf8')}\n\`\`\``).join('\n\n');
        const input = await this.page.$('textarea, [contenteditable="true"], .input-area textarea');
        await input?.fill(content);
    }

    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`Gemini: Sending prompt (${prompt.length} chars).`);
        const input = await this.page.$('textarea, [contenteditable="true"], .input-area textarea');
        await input?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('Gemini: Waiting for response...');
        try {
            await this.page.waitForSelector('[class*="loading"], [class*="generating"]', { state: 'detached', timeout: 120000 }).catch(() => {});
            await this.page.waitForSelector('.model-response-text, [class*="model-response"], .response-content', { timeout: 30000 });
            await this.page.waitForTimeout(1000);
            const responseText = await this.page.evaluate(() => {
                const messages = document.querySelectorAll('.model-response-text, [class*="model-response"], .response-content');
                return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
            });
            Logger.info(`Gemini: Response captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`Gemini response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
