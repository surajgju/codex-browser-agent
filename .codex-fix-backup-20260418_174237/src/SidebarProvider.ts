
    // Inline ghost text (cursor-like) – simplified version
    private registerGhostTextProvider() {
        vscode.languages.registerHoverProvider('*', {
            provideHover: async (document, position) => {
                // Show AI suggestion on hover (can be extended)
                return new vscode.Hover("💡 Codex: Press Ctrl+I to ask AI");
            }
        });
    }
