import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';
import { exec } from 'child_process';
import { promisify } from 'util';
import { Logger } from '../utils/logger';

const execAsync = promisify(exec);

export class ShadowWorkspace {
    private shadowRoot: string;
    private originalRoot: string;

    constructor(originalRoot: string) {
        this.originalRoot = originalRoot;
        this.shadowRoot = path.join(os.tmpdir(), `codex-shadow-${crypto.randomBytes(8).toString('hex')}`);
    }

    async create(): Promise<void> {
        await execAsync(`cp -r "${this.originalRoot}" "${this.shadowRoot}"`);
        Logger.info(`Shadow workspace created at ${this.shadowRoot}`);
    }

    async runScript(scriptPath: string): Promise<{ stdout: string; stderr: string; success: boolean }> {
        try {
            const { stdout, stderr } = await execAsync(`bash "${scriptPath}"`, { cwd: this.shadowRoot });
            return { stdout, stderr, success: true };
        } catch (err: any) {
            return { stdout: err.stdout, stderr: err.stderr, success: false };
        }
    }

    async showDiff(): Promise<string> {
        const { stdout } = await execAsync(`diff -urN "${this.originalRoot}" "${this.shadowRoot}" || true`);
        return stdout;
    }

    async accept(): Promise<void> {
        await execAsync(`rsync -a "${this.shadowRoot}/" "${this.originalRoot}/"`);
        Logger.info("Changes accepted from shadow workspace");
    }

    async cleanup(): Promise<void> {
        await execAsync(`rm -rf "${this.shadowRoot}"`);
    }
}
