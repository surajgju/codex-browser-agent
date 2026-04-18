import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class DeepSeekAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('deepseek', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        try {
            await this.page.goto('https://chat.deepseek.com', { waitUntil: 'domcontentloaded' });
            await this.page.waitForSelector('textarea, [contenteditable="true"]', { timeout: 10000 });
            Logger.info('DeepSeek: Logged in.');
        } catch (e) {
            Logger.error(`DeepSeek login failed: ${e}`);
            throw e;
        }
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`DeepSeek: Uploading ${filePaths.length} files.`);
        const fs = require('fs');
        const content = filePaths.map(p => `FILE: ${p}\n\`\`\`\n${fs.readFileSync(p, 'utf8')}\n\`\`\``).join('\n\n');
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(content);
    }

    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`DeepSeek: Sending prompt (${prompt.length} chars).`);
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('DeepSeek: Waiting for response...');
        try {
            // Wait for stop button to appear then disappear
            const stopBtn = await this.page.$('button[aria-label="Stop"], button:has-text("Stop")');
            if (stopBtn) {
                Logger.info('DeepSeek: Stop button found, waiting for it to disappear.');
                await this.page.waitForSelector('button[aria-label="Stop"], button:has-text("Stop")', { state: 'detached', timeout: 120000 });
            }
            // Wait for markdown content
            await this.page.waitForSelector('.ds-markdown, [class*="markdown"]', { timeout: 30000 });
            await this.page.waitForTimeout(2000);
            
            const responseText = await this.page.evaluate(() => {
                const messages = document.querySelectorAll('.ds-markdown, [class*="markdown"]');
                return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
            });
            Logger.info(`DeepSeek: Response captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`DeepSeek response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
