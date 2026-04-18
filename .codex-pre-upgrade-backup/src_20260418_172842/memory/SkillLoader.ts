import * as fs from "fs";
import * as path from "path";

export interface Skill {
    name: string;
    description: string;
    triggerKeywords: string[];
    promptTemplate: string;
    contextTemplate?: string;
    postActions?: { type: "command" | "prompt"; value: string }[];
}

export class SkillLoader {
    private skillsDir: string;

    constructor(workspaceFolder?: string) {
        this.skillsDir = path.join(workspaceFolder || process.cwd(), ".codex-memory/skills");
    }

    loadSkills(): Skill[] {
        if (!fs.existsSync(this.skillsDir)) return [];
        return fs.readdirSync(this.skillsDir)
            .filter(f => f.endsWith(".json"))
            .map(f => {
                try {
                    return JSON.parse(fs.readFileSync(path.join(this.skillsDir, f), "utf8")) as Skill;
                } catch {
                    return null;
                }
            })
            .filter((s): s is Skill => s !== null);
    }

    findRelevantSkills(prompt: string): Skill[] {
        const skills = this.loadSkills();
        const lowerPrompt = prompt.toLowerCase();
        return skills.filter(skill =>
            skill.triggerKeywords.some(kw => lowerPrompt.includes(kw.toLowerCase()))
        );
    }
}
