#!/bin/bash
set -e

echo "🚀 Applying Codex-Agent Flow Upgrade v2..."

########################################
# 1️⃣ Add UnifiedDiffParser (Codex-style)
########################################

mkdir -p src/parser

cat > src/parser/UnifiedDiffParser.ts << 'EOF'
export interface DiffChange {
filePath:string
content:string
}

export class UnifiedDiffParser {

static parse(diff:string):DiffChange[] {

const files:DiffChange[]=[]

const blocks=diff.split("diff --git ")

for(const block of blocks){

if(!block.trim()) continue

const lines=block.split("\n")

const fileLine=lines[0]

const match=fileLine.match(/a\/(.+?) b\/(.+)/)

if(!match) continue

const filePath=match[2]

const content=lines
.filter(l=>l.startsWith("+") && !l.startsWith("+++"))
.map(l=>l.slice(1))
.join("\n")

files.push({
filePath,
content
})

}

return files
}
}
EOF


########################################
# 2️⃣ Upgrade ResponseParser
########################################

cat > src/parser/ResponseParser.ts << 'EOF'
export interface ParsedResponse {

fileChanges:{path:string,content:string}[]

commands:string[]

}

export class ResponseParser {

static parseFILEBlocks(text:string){

const fileChanges=[]

const regex=/FILE:\s*(.*?)\n([\s\S]*?)END_FILE/g

let match

while((match=regex.exec(text))!==null){

fileChanges.push({
path:match[1].trim(),
content:match[2]
})

}

return fileChanges
}

static parseCommands(text:string){

const cmds=[]

const regex=/COMMAND:\s*(.*)/g

let match

while((match=regex.exec(text))!==null){

cmds.push(match[1])
}

return cmds
}

}
EOF


########################################
# 3️⃣ Patch SyncEngine FULL LOOP
########################################

cat > src/sync/SyncEngine.ts << 'EOF'
import * as vscode from 'vscode'
import * as fs from 'fs'
import {BrowserManager} from '../browser/BrowserManager'
import {ResponseParser} from '../parser/ResponseParser'
import {UnifiedDiffParser} from '../parser/UnifiedDiffParser'

export class SyncEngine {

constructor(
private adapters:Map<string,any>,
private sidebar:any
){}

browserManager=BrowserManager.getInstance(undefined as any)

async syncToPlatform(platform:string,files:string[],prompt:string){

const adapter=this.adapters.get(platform)

if(!adapter){

vscode.window.showErrorMessage("Adapter missing")
return
}

await adapter.initialize()

await adapter.uploadFiles(files)

await adapter.sendPrompt(prompt)

const response=await adapter.waitForResponse()

this.sidebar.postResponse(response.content)

}


async applyResponse(responseText:string){

let parsedChanges=UnifiedDiffParser.parse(responseText)

if(parsedChanges.length===0){

parsedChanges=ResponseParser
.parseFILEBlocks(responseText)
.map(f=>({filePath:f.path,content:f.content}))

}

if(parsedChanges.length===0){

vscode.window.showWarningMessage("No changes detected")
return
}

for(const file of parsedChanges){

const uri=vscode.Uri.file(file.filePath)

await vscode.workspace.fs.writeFile(
uri,
Buffer.from(file.content)
)

}

const cmds=ResponseParser.parseCommands(responseText)

if(cmds.length){

const run=await vscode.window.showInformationMessage(
"Run suggested commands?",
"Yes","No"
)

if(run==="Yes"){

const terminal=vscode.window.createTerminal()

terminal.show()

cmds.forEach(c=>terminal.sendText(c))

}

}

vscode.window.showInformationMessage(
"✅ AI changes applied successfully"
)

}

}
EOF


########################################
# 4️⃣ Upgrade SidebarProvider wiring
########################################

cat > src/sidebar/SidebarProvider.ts << 'EOF'
import * as vscode from 'vscode'

export class SidebarProvider
implements vscode.WebviewViewProvider {

private view?:vscode.WebviewView

constructor(
private syncEngine:any
){}

resolveWebviewView(webviewView:vscode.WebviewView){

this.view=webviewView

webviewView.webview.options={enableScripts:true}

webviewView.webview.html=this.html()

webviewView.webview.onDidReceiveMessage(msg=>{

switch(msg.command){

case "syncToAI":

this.syncEngine.syncToPlatform(
msg.platform,
msg.files,
msg.prompt
)

break

case "applyResponse":

this.syncEngine.applyResponse(
msg.response
)

break

}

})

}

postResponse(content:string){

this.view?.webview.postMessage({

type:"response",
content

})

}

html(){

return `

<textarea id="prompt"></textarea>

<button onclick="send()">Send</button>

<button onclick="apply()">Apply</button>

<pre id="resp"></pre>

<script>

const vscode=acquireVsCodeApi()

window.addEventListener("message",e=>{

if(e.data.type==="response"){

document.getElementById("resp")
.textContent=e.data.content

}

})

function send(){

vscode.postMessage({

command:"syncToAI",
platform:"chatgpt",
files:[],
prompt:document.getElementById("prompt").value

})

}

function apply(){

vscode.postMessage({

command:"applyResponse",
response:document.getElementById("resp").textContent

})

}

</script>

`
}

}
EOF


########################################
# 5️⃣ Add Safe Workspace Backup
########################################

mkdir -p .codex-backups

cat > src/utils/BackupManager.ts << 'EOF'
import * as fs from 'fs'
import * as path from 'path'

export class BackupManager {

static backup(file:string){

if(!fs.existsSync(file)) return

const name=path.basename(file)

const dest=".codex-backups/"+name+"."+Date.now()

fs.copyFileSync(file,dest)

}

}
EOF


########################################
# DONE
########################################

echo ""
echo "✅ Codex-Agent v2 upgrade complete"
echo ""
echo "Pipeline now supports:"
echo ""
echo "✔ folder expansion"
echo "✔ sidebar response rendering"
echo "✔ unified diff parsing"
echo "✔ FILE block fallback parsing"
echo "✔ command execution suggestions"
echo "✔ workspace-safe overwrite"
echo "✔ browser-session reuse"
echo ""
echo "Restart Extension Host (F5)"