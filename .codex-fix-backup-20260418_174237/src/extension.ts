import * as vscode from "vscode";
import { SidebarProvider } from "./sidebar/SidebarProvider";
import { SyncEngine } from "./sync/SyncEngine";
import { CommandRunner } from "./commands/CommandRunner";
import { FileWatcher } from "./context/FileWatcher";
import { ContextEngine } from "./context/ContextEngine";
import { Logger } from "./utils/logger";
import { ErrorHandler } from "./utils/errorHandler";
import { StorageHelper } from "./utils/storage";
import { Config } from "./utils/config";
import { WorkspaceMap } from "./memory/WorkspaceMap";

export function activate(context: vscode.ExtensionContext) {
    Logger.info("Codex Browser Agent v3 (Memory) activated");

    const storage = new StorageHelper(context);
    const config = new Config();
    const errorHandler = new ErrorHandler();
    const contextEngine = new ContextEngine();
    const fileWatcher = new FileWatcher(contextEngine);
    const syncEngine = new SyncEngine(config, errorHandler, storage);
    const commandRunner = new CommandRunner(config, errorHandler);

    Logger.info("All engine singletons instantiated.");

    // Initialize workspace map on activation
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (workspaceFolder) {
        const wm = new WorkspaceMap();
        const map = wm.generate(workspaceFolder);
        Logger.info(`Workspace map generated with ${map.length} files.`);
    }

    const sidebarProvider = new SidebarProvider(
        context.extensionUri,
        contextEngine,
        syncEngine,
        commandRunner,
        config
    );

    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(
            "codex-browser-agent-sidebar",
            sidebarProvider
        )
    );

    context.subscriptions.push(
        vscode.commands.registerCommand("codex-browser-agent.openSidebar", () => {
            Logger.info("Command manually triggered: codex-browser-agent.openSidebar");
            vscode.commands.executeCommand("workbench.view.extension.codex-browser-agent-sidebar");
        }),
        vscode.commands.registerCommand("codex-browser-agent.syncSelected", async () => {
            Logger.info("Command manually triggered: codex-browser-agent.syncSelected");
            await syncEngine.syncSelected();
        }),
        vscode.commands.registerCommand("codex-browser-agent.applyResponse", async (responseData: any) => {
            Logger.info("Command manually triggered: codex-browser-agent.applyResponse");
            await syncEngine.applyResponse(responseData);
        }),
        vscode.commands.registerCommand("codex-browser-agent.runCommand", async (command: string) => {
            Logger.info(`Command manually triggered: codex-browser-agent.runCommand (Command: ${command})`);
            await commandRunner.run(command);
        })
    );

    fileWatcher.start();
    context.subscriptions.push(fileWatcher);
}

export function deactivate() {
    Logger.info("Codex Browser Agent deactivated");
}

    // Production-grade features initialization
    import { ShadowWorkspace } from './speculative/ShadowWorkspace';
    import { ModelRouter } from './orchestrator/ModelRouter';
    import { DiffApplier } from './diff/DiffApplier';

    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || process.cwd();
    const shadow = new ShadowWorkspace(workspaceRoot);
    const diffApplier = new DiffApplier();
    // Register speculative execution command
    vscode.commands.registerCommand('codex-browser-agent.speculativeApply', async () => {
        await shadow.create();
        const diff = await shadow.showDiff();
        const accept = await vscode.window.showInformationMessage('Apply changes?', 'Yes', 'No');
        if (accept === 'Yes') await shadow.accept();
        await shadow.cleanup();
    });
