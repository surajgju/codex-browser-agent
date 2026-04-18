import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ChatGPTAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('chatgpt', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        try {
            await this.page.goto('https://chat.openai.com', { waitUntil: 'domcontentloaded' });
            await this.page.waitForSelector('textarea[placeholder*="Message"], [contenteditable="true"]', { timeout: 10000 });
            Logger.info('ChatGPT: Logged in.');
        } catch (e) {
            Logger.error(`ChatGPT login failed: ${e}`);
            throw e;
        }
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`ChatGPT: Uploading ${filePaths.length} files.`);
        const attachButton = await this.page.$('button[aria-label="Attach files"], button[aria-label*="attach" i]');
        if (attachButton) {
            await attachButton.click();
            const fileInput = await this.page.$('input[type="file"]');
            if (fileInput) {
                await fileInput.setInputFiles(filePaths);
                await this.page.waitForTimeout(2000);
                (this as any)._usedAttach = true;
            }
        } else {
            const fs = require('fs');
            const contents = filePaths.map(p => `FILE: ${p}\n\`\`\`\n${fs.readFileSync(p, 'utf8')}\n\`\`\``).join('\n\n');
            const textarea = await this.page.$('textarea, [contenteditable="true"]');
            if (textarea) {
                await textarea.fill(contents);
                (this as any)._hasUploadedViaFallback = true;
            }
        }
    }

    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`ChatGPT: Sending prompt (${prompt.length} chars).`);
        const textarea = await this.page.$('textarea, [contenteditable="true"]');
        if (!textarea) return;
        if ((this as any)._hasUploadedViaFallback) {
            await textarea.type('\n\n' + prompt);
        } else {
            await textarea.fill(prompt);
        }
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('ChatGPT: Waiting for response...');
        try {
            await this.page.waitForSelector('button[aria-label="Stop generating"], button:has-text("Stop")', { state: 'detached', timeout: 120000 }).catch(() => {});
            await this.page.waitForSelector('[data-message-author-role="assistant"]', { timeout: 30000 });
            await this.page.waitForTimeout(1000);
            const responseText = await this.page.evaluate(() => {
                const messages = document.querySelectorAll('[data-message-author-role="assistant"] .markdown');
                return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
            });
            Logger.info(`ChatGPT: Response captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`ChatGPT response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
