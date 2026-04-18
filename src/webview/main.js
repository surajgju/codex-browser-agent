(function() {
    const vscode = acquireVsCodeApi();
    const oldState = vscode.getState() || { files: [] };
    
    const fileListEl = document.getElementById('file-list');
    const selectBtn = document.getElementById('select-files');
    const syncBtn = document.getElementById('sync-button');
    const platformSelect = document.getElementById('platform-select');
    const promptInput = document.getElementById('prompt-input');
    const responseContent = document.getElementById('response-content');
    
    function log(msg) {
        console.log(`[Codex Webview] ${msg}`);
    }
    
    function renderFiles() {
        fileListEl.innerHTML = oldState.files.map(f => `<li>${f}</li>`).join('');
        log(`Rendered ${oldState.files.length} files`);
    }
    renderFiles();
    
    window.addEventListener('message', event => {
        const message = event.data;
        log(`Received message type: ${message.type}`);
        switch (message.type) {
            case 'contextUpdate':
                oldState.files = message.files;
                vscode.setState(oldState);
                renderFiles();
                break;
            case 'config':
                log('Config received');
                break;
            case 'response':
                responseContent.textContent = message.content;
                log(`Response displayed (${message.content.length} chars)`);
                break;
        }
    });
    
    selectBtn.addEventListener('click', () => {
        log('Select files clicked');
        vscode.postMessage({ command: 'selectFiles' });
    });
    
    syncBtn.addEventListener('click', () => {
        const platform = platformSelect.value;
        const prompt = promptInput.value;
        log(`Sync clicked: platform=${platform}, prompt length=${prompt.length}`);
        vscode.postMessage({
            command: 'syncToAI',
            platform,
            files: oldState.files,
            prompt
        });
    });
    
    document.getElementById('apply-response').addEventListener('click', () => {
        const resp = responseContent.textContent;
        log(`Apply clicked, response length=${resp.length}`);
        vscode.postMessage({ command: 'applyResponse', response: resp });
    });
    
    document.getElementById('run-command').addEventListener('click', () => {
        const cmd = prompt('Enter command to run:');
        if (cmd) {
            log(`Run command: ${cmd}`);
            vscode.postMessage({ command: 'runCommand', command: cmd });
        }
    });
})();
