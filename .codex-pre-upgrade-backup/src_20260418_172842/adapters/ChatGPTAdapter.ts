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
            // Wait for the assistant response element to appear
            await this.page.waitForSelector('[data-message-author-role="assistant"] .markdown, [data-message-author-role="assistant"]', { timeout: 30000 });
            
            let lastLength = 0;
            let stableTicks = 0;
            let responseText = '';

            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000); // 1 second tick
                
                responseText = await this.page.evaluate(() => {
                    const messages = document.querySelectorAll('[data-message-author-role="assistant"] .markdown, [data-message-author-role="assistant"]');
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
            
            Logger.info(`ChatGPT: Response completely captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`ChatGPT response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
