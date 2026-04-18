import { PlatformAdapter } from '../browser/PlatformAdapter';
import { Logger } from '../utils/logger';

export class ModelRouter {
    constructor(
        private fastAdapter: PlatformAdapter,   // e.g., Gemini Flash
        private heavyAdapter: PlatformAdapter    // e.g., DeepSeek Coder
    ) {}

    async route(prompt: string, context: string): Promise<string> {
        // Determine complexity: if prompt contains "refactor", "architecture", "large" → heavy
        const isComplex = /refactor|architecture|large|many files|optimize/i.test(prompt);
        const adapter = isComplex ? this.heavyAdapter : this.fastAdapter;
        Logger.info(`Routing to ${isComplex ? 'heavy' : 'fast'} model`);
        await adapter.initialize();
        await adapter.sendPrompt(prompt + "\n\nContext:\n" + context);
        const response = await adapter.waitForResponse();
        return response.content;
    }
}
