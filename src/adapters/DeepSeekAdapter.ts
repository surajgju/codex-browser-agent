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
            // Wait for the response container to appear
            await this.page.waitForSelector('.ds-markdown, [class*="markdown"]', { timeout: 30000 });
            
            let lastLength = 0;
            let stableTicks = 0;
            let responseText = '';

            // Continuously poll the DOM until the text length stays exactly the same for 4 seconds
            // This guarantees we capture the ENTIRE streaming payload regardless of platform stop buttons
            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000); // 1 second tick
                
                responseText = await this.page.evaluate(() => {
                    const messages = document.querySelectorAll('.ds-markdown, [class*="markdown"]');
                    return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
                });

                if (responseText.length > 0 && responseText.length === lastLength) {
                    stableTicks++;
                    if (stableTicks >= 4) {
                        break; // Text has stopped streaming
                    }
                } else {
                    stableTicks = 0; // Reset if still growing
                    lastLength = responseText.length;
                }
            }
            
            Logger.info(`DeepSeek: Response completely captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`DeepSeek response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
