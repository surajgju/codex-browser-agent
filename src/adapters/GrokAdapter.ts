import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class GrokAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('grok', browserManager); }
    
    async ensureLoggedIn(): Promise<void> {
        Logger.info('Grok: Starting ensureLoggedIn logic...');
        await this.page.goto('https://grok.x.ai');
        await this.page.waitForSelector('textarea', { timeout: 0 });
        Logger.info('Grok: Logged in.');
    }
    
    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`Grok: Uploading ${filePaths.length} files as text...`);
        const content = filePaths.map(p => `${p}:\n${require('fs').readFileSync(p, 'utf8')}`).join('\n');
        const textarea = await this.page.$('textarea');
        await textarea?.fill(content);
    }
    
    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`Grok: Sending prompt (${prompt.length} chars).`);
        const textarea = await this.page.$('textarea');
        await textarea?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }
    
    async waitForResponse(): Promise<AIResponse> {
        Logger.info('Grok: Waiting for response...');
        try {
            await this.page.waitForSelector('.message-content', { timeout: 30000 });
            
            let lastLength = 0;
            let stableTicks = 0;
            let responseText = '';

            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000);
                responseText = await this.page.evaluate(() => {
                    const messages = document.querySelectorAll('.message-content');
                    return messages.length > 0 ? messages[messages.length - 1]?.textContent || '' : '';
                });
                
                if (responseText.length > 0 && responseText.length === lastLength) {
                    stableTicks++;
                    if (stableTicks >= 4) {
                        break;
                    }
                } else {
                    stableTicks = 0;
                    lastLength = responseText.length;
                }
            }
            
            Logger.info(`Grok: Response completely captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`Grok response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
