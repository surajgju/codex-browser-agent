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
            vscode.commands.executeCommand("workbench.view.extension.codex-browser-agent-sidebar");
        }),
        vscode.commands.registerCommand("codex-browser-agent.syncSelected", async () => {
            await syncEngine.syncSelected();
        }),
        vscode.commands.registerCommand("codex-browser-agent.applyResponse", async (responseData: any) => {
            await syncEngine.applyResponse(responseData);
        }),
        vscode.commands.registerCommand("codex-browser-agent.runCommand", async (command: string) => {
            await commandRunner.run(command);
        })
    );

    fileWatcher.start();
    context.subscriptions.push(fileWatcher);
}

export function deactivate() {
    Logger.info("Codex Browser Agent deactivated");
}
