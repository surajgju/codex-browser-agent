import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { Logger } from '../utils/logger';

export class ContextEngine {
    private selectedFiles: Set<string> = new Set();
    private fileContentCache: Map<string, string> = new Map();
    
    addSelectedFiles(filePaths: string[]) {
        Logger.info(`ContextEngine: Adding ${filePaths.length} selected files.`);
        filePaths.forEach(p => this.selectedFiles.add(p));
        this.updateCache(filePaths);
    }
    
    private updateCache(filePaths: string[]) {
        for (const p of filePaths) {
            if (fs.existsSync(p) && fs.statSync(p).isFile()) {
                this.fileContentCache.set(p, fs.readFileSync(p, 'utf8'));
            }
        }
    }
    
    getRelevantFiles(): string[] {
        Logger.info(`ContextEngine: Retrieving relevant files (Count: ${this.selectedFiles.size}).`);
        return Array.from(this.selectedFiles);
    }
    
    getFileContents(files: string[]): Record<string, string> {
        Logger.info(`ContextEngine: Reading contents for ${files.length} selected files.`);
        const result: Record<string, string> = {};
        for (const f of files) {
            if (fs.existsSync(f)) {
                result[f] = fs.readFileSync(f, 'utf8');
            }
        }
        return result;
    }
    
    clear() {
        Logger.info('ContextEngine: Clearing file cache and deselecting files.');
        this.selectedFiles.clear();
        this.fileContentCache.clear();
    }
}
