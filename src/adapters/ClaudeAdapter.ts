import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ClaudeAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('claude', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        await this.navigateToChatIfNeeded('https://claude.ai');
        await this.page.waitForSelector('[contenteditable="true"]', { timeout: 10000 });
        Logger.info('Claude: Logged in and ready.');
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`Claude: Uploading ${filePaths.length} files.`);
        const attachBtn = await this.page.$('button[aria-label="Attach files"]');
        if (attachBtn) {
            await attachBtn.click();
            const fileInput = await this.page.$('input[type="file"]');
            await fileInput?.setInputFiles(filePaths);
        } else {
            const fs = require('fs');
            const content = filePaths.map(p => `FILE: ${p}\n\`\`\`\n${fs.readFileSync(p, 'utf8')}\n\`\`\``).join('\n\n');
            const editor = await this.page.$('[contenteditable="true"]');
            await editor?.fill(content);
        }
    }

    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`Claude: Sending prompt (${prompt.length} chars).`);
        const editor = await this.page.$('[contenteditable="true"]');
        await editor?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('Claude: Waiting for response...');
        try {
            await this.page.waitForSelector('.prose', { timeout: 30000 });
            
            let lastLength = 0;
            let stableTicks = 0;
            let responseText = '';

            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000);
                responseText = await this.page.evaluate(() => {
                    const messages = document.querySelectorAll('.prose');
                    return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
                });

                if (responseText.length > 0 && responseText.length === lastLength) {
                    stableTicks++;
                    if (stableTicks >= 4) break;
                } else {
                    stableTicks = 0;
                    lastLength = responseText.length;
                }
            }
            
            Logger.info(`Claude: Response completely captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`Claude response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
