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
