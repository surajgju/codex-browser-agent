#!/bin/bash
set -e

echo "🔁 Patching adapters to reuse existing chat session..."

# Backup adapters
mkdir -p .codex-session-backup
cp src/adapters/*.ts .codex-session-backup/

# ----------------------------------------------------------------------
# 1. Update PlatformAdapter base class: add method to check if already on chat page
# ----------------------------------------------------------------------
cat >> src/browser/PlatformAdapter.ts << 'EOF'

    /**
     * Check if we are already on the expected chat page.
     * Override in specific adapters.
     */
    protected async isOnChatPage(): Promise<boolean> {
        const url = this.page.url();
        // Default: return true if URL contains the platform's domain and no login parameters
        return url.includes(this.platformId) && !url.includes('login') && !url.includes('signin');
    }

    /**
     * Navigate only if not already on chat page.
     */
    protected async navigateToChatIfNeeded(chatUrl: string): Promise<void> {
        if (await this.isOnChatPage()) {
            Logger.info(`${this.platformId}: Already on chat page, skipping navigation`);
            return;
        }
        Logger.info(`${this.platformId}: Navigating to ${chatUrl}`);
        await this.page.goto(chatUrl, { waitUntil: 'domcontentloaded' });
    }
EOF

# ----------------------------------------------------------------------
# 2. Update ChatGPTAdapter.ts to avoid re-navigation
# ----------------------------------------------------------------------
cat > src/adapters/ChatGPTAdapter.ts << 'EOF'
import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ChatGPTAdapter extends PlatformAdapter {
    constructor(browserManager: any) { super('chatgpt', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        await this.navigateToChatIfNeeded('https://chat.openai.com');
        await this.page.waitForSelector('textarea[placeholder*="Message"], [contenteditable="true"]', { timeout: 10000 });
        Logger.info('ChatGPT: Logged in and ready.');
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
            await this.page.waitForSelector('[data-message-author-role="assistant"] .markdown, [data-message-author-role="assistant"]', { timeout: 30000 });
            let lastLength = 0;
            let stableTicks = 0;
            let responseText = '';
            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000);
                responseText = await this.page.evaluate(() => {
                    const messages = document.querySelectorAll('[data-message-author-role="assistant"] .markdown, [data-message-author-role="assistant"]');
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
            Logger.info(`ChatGPT: Response captured (${responseText.length} chars).`);
            return { content: responseText };
        } catch (e) {
            Logger.error(`ChatGPT response wait failed: ${e}`);
            return { content: '' };
        }
    }
}
EOF

# ----------------------------------------------------------------------
# 3. Similarly update other adapters (Gemini, Claude, Grok, DeepSeek)
#    We'll use a loop for brevity
# ----------------------------------------------------------------------
for adapter in Gemini Claude Grok DeepSeek; do
    lower=$(echo "$adapter" | tr '[:upper:]' '[:lower:]')
    url=""
    case $lower in
        gemini) url="https://gemini.google.com" ;;
        claude) url="https://claude.ai" ;;
        grok) url="https://grok.x.ai" ;;
        deepseek) url="https://chat.deepseek.com" ;;
    esac
    cat > "src/adapters/${adapter}Adapter.ts" << EOF
import { PlatformAdapter, AIResponse } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ${adapter}Adapter extends PlatformAdapter {
    constructor(browserManager: any) { super('${lower}', browserManager); }

    async ensureLoggedIn(): Promise<void> {
        await this.navigateToChatIfNeeded('${url}');
        await this.page.waitForSelector('textarea, [contenteditable="true"]', { timeout: 10000 });
        Logger.info('${adapter}: Logged in and ready.');
    }

    async uploadFiles(filePaths: string[]): Promise<void> {
        Logger.info(`${adapter}: Uploading ${filePaths.length} files.`);
        const fs = require('fs');
        const content = filePaths.map(p => \`FILE: \${p}\n\`\`\`\n\${fs.readFileSync(p, 'utf8')}\n\`\`\`\`).join('\n\n');
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(content);
    }

    async sendPrompt(prompt: string): Promise<void> {
        Logger.info(`${adapter}: Sending prompt (\${prompt.length} chars).`);
        const input = await this.page.$('textarea, [contenteditable="true"]');
        await input?.fill(prompt);
        await this.page.keyboard.press('Enter');
    }

    async waitForResponse(): Promise<AIResponse> {
        Logger.info('${adapter}: Waiting for response...');
        try {
            await this.page.waitForSelector('.markdown, .prose, .ds-markdown, .message-content', { timeout: 30000 });
            let lastLength = 0, stableTicks = 0, responseText = '';
            for (let i = 0; i < 120; i++) {
                await this.page.waitForTimeout(1000);
                responseText = await this.page.evaluate(() => {
                    const sel = '.markdown, .prose, .ds-markdown, .message-content, .model-response-text';
                    const el = document.querySelector(sel);
                    return el?.textContent || '';
                });
                if (responseText.length > 0 && responseText.length === lastLength) {
                    stableTicks++;
                    if (stableTicks >= 4) break;
                } else {
                    stableTicks = 0;
                    lastLength = responseText.length;
                }
            }
            return { content: responseText };
        } catch (e) {
            Logger.error(`${adapter} response wait failed: \${e}`);
            return { content: '' };
        }
    }
}
EOF
    echo "✅ Updated ${adapter}Adapter.ts"
done

# ----------------------------------------------------------------------
# 4. Ensure BrowserManager does not close context between calls
#    (It already persists, but we add a log)
# ----------------------------------------------------------------------
if ! grep -q "Reusing existing browser context" src/browser/BrowserManager.ts; then
    sed -i.bak '/Logger\.info(`BrowserManager: Reusing existing page/ a\        Logger.info(`BrowserManager: Reusing existing browser context for ${platform}`);' src/browser/BrowserManager.ts
fi

# ----------------------------------------------------------------------
# 5. Modify SyncEngine to NOT re-initialize adapter if already initialized
#    (AgentLoop already calls initialize, but we can avoid duplicate work)
# ----------------------------------------------------------------------
SYNC_FILE="src/sync/SyncEngine.ts"
if grep -q "await adapter.initialize()" "$SYNC_FILE"; then
    # Add a flag to track if adapter was already initialized
    perl -i -pe 's/await adapter\.initialize\(\);/if (!adapter.initialized) { await adapter.initialize(); adapter.initialized = true; }/' "$SYNC_FILE"
    echo "✅ SyncEngine patched to avoid re-initializing adapter unnecessarily"
fi

# ----------------------------------------------------------------------
# 6. Final instructions
# ----------------------------------------------------------------------
echo ""
echo "✅ All adapters now preserve existing chat session."
echo "   - They will NOT navigate to the chat URL if already on it."
echo "   - The same Playwright page is reused across multiple syncs."
echo "   - Conversation history is maintained because the page is not refreshed."
echo ""
echo "Next steps:"
echo "  npm run compile"
echo "  Reload VS Code"
echo "  Test: start a conversation manually in ChatGPT, then run a Codex sync – it should continue the same chat thread."