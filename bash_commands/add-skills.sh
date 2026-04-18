#!/bin/bash
set -e

echo "🧩 Adding Second-Brain Skills to Codex Browser Agent..."

# Ensure skills directory exists
mkdir -p .codex-memory/skills

########################################
# 1. Brand & Voice Generator Skill
########################################
cat > .codex-memory/skills/brand-voice-generator.skill.json << 'EOF'
{
  "name": "brand-voice-generator",
  "description": "Generate tone-of-voice and brand-system files for presentations and content",
  "triggerKeywords": ["brand", "voice", "tone", "brand system", "visual identity", "color palette"],
  "promptTemplate": "Help me create a brand system for {project}. Walk me through defining: 1) Brand basics (name, description, primary use case), 2) 10 color values, 3) Typography (heading, body, code fonts), 4) Logo/icon assets, 5) Voice personality, vocabulary, and sentence patterns. Create brand.json, config.json, brand-system.md, and tone-of-voice.md files.",
  "contextTemplate": "Workspace: {workspace}\nFiles: {files}\nRecent iterations: {iterations}",
  "postActions": [
    { "type": "command", "value": "echo 'Brand files created. Review .codex-memory/brands/' }
  ]
}
EOF

########################################
# 2. MCP Client Skill
########################################
cat > .codex-memory/skills/mcp-client.skill.json << 'EOF'
{
  "name": "mcp-client",
  "description": "Connect to external MCP servers (Zapier, GitHub, etc.) with progressive disclosure",
  "triggerKeywords": ["mcp", "zapier", "model context protocol", "connect server", "mcp tools"],
  "promptTemplate": "Configure MCP client to connect to {server_name}. Use the example config at references/example-mcp-config.json. List available tools and document any gotchas in CLAUDE.md.",
  "contextTemplate": "Current MCP config: {mcp_config}\nAvailable servers: {servers}",
  "postActions": [
    { "type": "prompt", "value": "Test the MCP server tools and update CLAUDE.md with any quirks or required argument formats." }
  ]
}
EOF

########################################
# 3. PPTX Generator Skill
########################################
cat > .codex-memory/skills/pptx-generator.skill.json << 'EOF'
{
  "name": "pptx-generator",
  "description": "Generate professional, on-brand presentation slides and LinkedIn carousels using python-pptx",
  "triggerKeywords": ["presentation", "slides", "pptx", "carousel", "linkedin carousel", "slide deck"],
  "promptTemplate": "Create a presentation with {num_slides} slides about {topic}. Use the brand system at brands/{brand_name}/. Follow the visual-first layout selection: prefer multi-card, stats, two-column, circular-hero, or quote layouts over content-slide.",
  "contextTemplate": "Brand files: brand.json, config.json, brand-system.md, tone-of-voice.md\nAvailable layouts: title, content, stats, two-column, multi-card, floating-cards, circular-hero, quote, chart, code.",
  "postActions": [
    { "type": "command", "value": "python scripts/generate_pptx.py --output {output_file}" }
  ]
}
EOF

########################################
# 4. SOP Creator Skill
########################################
cat > .codex-memory/skills/sop-creator.skill.json << 'EOF'
{
  "name": "sop-creator",
  "description": "Create runbooks, playbooks, and technical documentation that people actually follow",
  "triggerKeywords": ["sop", "runbook", "documentation", "process", "playbook", "checklist", "standard operating procedure"],
  "promptTemplate": "Create an SOP for {process_name}. Follow the universal structure: Definition of Done, When to Use, Prerequisites, The Process (numbered steps), Verify Completion, When Things Go Wrong, Questions?. Be specific with numbers, names, thresholds. Use action-first steps and put warnings before dangerous steps.",
  "contextTemplate": "Existing documentation: {existing_docs}\nWorkspace structure: {workspace_tree}",
  "postActions": [
    { "type": "prompt", "value": "Review the SOP for clarity and ensure all placeholders are filled with concrete values." }
  ]
}
EOF

########################################
# 5. Skill Creator Skill
########################################
cat > .codex-memory/skills/skill-creator.skill.json << 'EOF'
{
  "name": "skill-creator",
  "description": "Guide for creating effective skills that extend Claude's capabilities",
  "triggerKeywords": ["create skill", "new skill", "skill development", "extend claude"],
  "promptTemplate": "Help me create a new skill for {purpose}. Follow the skill anatomy: SKILL.md with YAML frontmatter (name, description) and Markdown instructions. Bundle optional scripts/, references/, assets/. Only add context Claude doesn't already have. Use progressive disclosure.",
  "contextTemplate": "Existing skills: {skills_list}\nSkill template: .claude/skills/template/",
  "postActions": [
    { "type": "command", "value": "python .claude/skills/skill-creator/scripts/init_skill.py {skill_name}" }
  ]
}
EOF

########################################
# 6. Remotion Video Creator Skill
########################################
cat > .codex-memory/skills/remotion-video-creator.skill.json << 'EOF'
{
  "name": "remotion-video-creator",
  "description": "Create programmatic videos using React with Remotion",
  "triggerKeywords": ["remotion", "video", "animation", "react video", "mp4", "composition"],
  "promptTemplate": "Create a Remotion video with {description}. Use the Remotion project at {project_path}. Focus on one composition at a time. Include animations, text effects, and assets as needed.",
  "contextTemplate": "Remotion project structure: {project_tree}\nAvailable components: {components}",
  "postActions": [
    { "type": "command", "value": "cd {project_path} && npm run dev" }
  ]
}
EOF

########################################
# Summary
########################################
echo ""
echo "✅ Skills added to .codex-memory/skills/"
echo ""
echo "Installed skills:"
ls -1 .codex-memory/skills/*.skill.json 2>/dev/null | xargs -n1 basename
echo ""
echo "These skills will be automatically loaded by the RetrievalEngine"
echo "and injected into prompts when trigger keywords match."
echo ""
echo "Next steps:"
echo "1. Customize each skill's promptTemplate and postActions for your workflows"
echo "2. Add brand files for PPTX Generator (use Brand & Voice Generator first)"
echo "3. Test with a sync: 'Create a presentation about our Q2 roadmap'"