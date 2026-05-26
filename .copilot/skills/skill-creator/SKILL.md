# Skill Creator

Create new skills, improve existing skills, and verify skill quality through structured testing. Adapted from Anthropic's skill-creator for VS Code Copilot.

## When to Use

- User says "create a skill", "make a skill", "turn this into a skill"
- User wants to capture a working workflow as a reusable skill
- User wants to improve or test an existing skill
- User says "this skill isn't working well" or "optimize this skill"

## Skill Location

This workspace has TWO skill scopes:

- **User-level** (applies to every workspace): `C:\Users\asalmon\.copilot\skills\<skill-name>\SKILL.md`
- **Workspace-level** (this repo only): `c:\Projects\TechCrash2026\.copilot\skills\<skill-name>\SKILL.md`

Pick the scope deliberately. Generic skills (e.g. `skill-creator`, `de10lite-board-and-build`) belong at user level. Project-specific skills (e.g. `challenge-publication`) belong in the workspace.

---

## Creating a Skill

### Step 1: Capture Intent

Start by understanding what the user wants. The current conversation may already contain a workflow worth capturing. If so, extract answers from context first.

Ask (or infer from conversation):
1. What should this skill enable? (the core capability)
2. When should it trigger? (user phrases, contexts, keywords)
3. What's the expected output format?
4. Are there edge cases or constraints?
5. What tools/files/commands does it need?

If the conversation already demonstrated a working workflow, summarize what you observed and confirm with the user before proceeding.

### Step 2: Research

Before writing, gather context:
- Check both skill scopes for similar existing skills (avoid duplication)
- Read any related SKILL.md files to understand conventions
- If the skill wraps an API or tool, check its documentation
- Look at the user's actual files/scripts that the skill will reference

### Step 3: Write the SKILL.md

#### File Structure

```
skill-name/
├── SKILL.md          (required — the skill instructions)
└── references/       (optional — large reference docs loaded on demand)
    ├── api-guide.md
    └── examples.md
```

#### SKILL.md Anatomy

Every SKILL.md has two parts:

**1. Frontmatter block** — appears in copilot-instructions.md skill list:
```yaml
<skill>
<name>skill-name</name>
<description>What it does and when to trigger. Be slightly pushy —
list specific trigger words/phrases so the skill fires reliably.
TRIGGER: user says "keyword1", "keyword2", "phrase3".</description>
<file>c:\path\to\SKILL.md</file>
</skill>
```

**2. Body** — the actual instructions Copilot follows when the skill is loaded.

#### Writing the Body

**Use imperative form.** "Read the file", "Run the command", not "You should read the file."

**Explain the why.** Instead of heavy-handed MUSTs, explain reasoning so the model understands importance. If you find yourself writing ALWAYS or NEVER in caps, reframe with reasoning. Exception: safety-critical rules deserve strong language (example: the Git Rules HARD STOP in this repo's copilot-instructions.md).

**Progressive disclosure.** Keep SKILL.md under 500 lines. For large reference material:
- Put it in `references/` subdirectory
- Add clear pointers in SKILL.md: "For API details, read `references/api-guide.md`"
- Include a brief table of contents for reference files over 300 lines

**Define output formats explicitly:**
```markdown
## Report Structure
Use this exact template:
# [Title]
## Summary
## Findings
## Next Steps
```

**Include examples** — they're the most effective way to communicate expectations:
```markdown
## Commit Message Format
Example 1:
  Input: Added user authentication with JWT tokens
  Output: feat(auth): implement JWT-based authentication

Example 2:
  Input: Fixed crash when file not found
  Output: fix: handle missing file gracefully in loader
```

**Domain organization** — when a skill supports multiple variants:
```
my-skill/
├── SKILL.md              (workflow + selection logic)
└── references/
    ├── variant-a.md
    └── variant-b.md
```
SKILL.md determines which variant applies, then points to the right reference file. This keeps context lean.

#### Description Writing Tips

The description is the primary trigger mechanism. Copilot sees skill names + descriptions and decides whether to load the full SKILL.md.

Good descriptions:
- State what the skill does AND specific trigger contexts
- Are slightly "pushy" — list extra trigger words to avoid under-triggering
- Include TRIGGER line with specific user phrases

Bad descriptions:
- Too generic: "Helps with testing" (when would this NOT apply?)
- Too narrow: "Run test_wva_48elem" (misses the general case)
- Missing triggers: doesn't list the phrases users actually say

**Example:**
```
Deploy compiled ISA files from local Windows to remote Linux test workspaces
via Z: drive or SSH/SCP. TRIGGER: user says "deploy instructions",
"copy ISA to linux", "upload instructions", "sync ISA files".
```

### Step 4: Register the Skill

After creating SKILL.md, add the skill entry to the appropriate `copilot-instructions.md` file's skill list AND to the `<skills>` block so it appears in context.

### Step 5: Test the Skill

See "Testing a Skill" below.

---

## Testing a Skill

Since we don't have isolated subagent eval runners, use this practical approach:

### Quick Smoke Test

1. Write 2-3 realistic user prompts that should trigger the skill
2. For each prompt, mentally walk through the SKILL.md instructions — do they lead to the right outcome?
3. Try one prompt in a fresh conversation to see if the skill triggers and the output is correct

### Manual Test Cases

Create a lightweight `evals.json` in the skill directory (optional but useful for complex skills):

```json
{
  "skill_name": "my-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "A realistic user prompt",
      "expected_output": "Description of what should happen",
      "expectations": [
        "The output includes X",
        "The command Y was executed",
        "File Z was created with correct content"
      ]
    }
  ]
}
```

### Trigger Testing

For each test prompt, check:
- Does the skill get loaded? (it should appear in the skill list match)
- Does the model follow the instructions correctly?
- Are there steps where the model goes off-script or gets confused?

### Common Failure Modes

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Skill never triggers | Description too narrow or missing trigger words | Add more trigger phrases |
| Skill triggers for wrong requests | Description too broad | Narrow the trigger conditions |
| Model skips steps | Instructions unclear or too long | Simplify, add examples |
| Model invents its own approach | Instructions too vague | Be more specific, add "Do NOT..." guards |
| Wrong output format | No format examples | Add explicit format template with examples |

---

## Improving an Existing Skill

### Step 1: Diagnose

Read the current SKILL.md and identify the problem:
- **Under-triggering**: Skill doesn't fire when it should → fix description
- **Over-triggering**: Skill fires when it shouldn't → narrow description
- **Wrong output**: Skill fires but produces bad results → fix instructions
- **Missing steps**: Workflow has gaps → add the missing pieces
- **Too verbose**: Model wastes time on unnecessary steps → trim instructions

### Step 2: Review Execution Patterns

If available, look at recent conversations where the skill was used:
- Did the model follow all steps?
- Where did it deviate?
- What did the user correct?

If the model repeatedly writes similar helper scripts or takes the same multi-step approach, that's a signal to bundle that script into the skill.

### Step 3: Apply Changes

**Generalize from specific feedback.** A fix for one test case should improve all similar cases, not just overfit to the example. Avoid fiddly, narrow patches — think about what general principle was missing.

**Keep the prompt lean.** Remove instructions that aren't pulling their weight. If the model wastes time on something, cut or simplify the instruction causing it.

**Explain the why.** If the model keeps ignoring an instruction, it may not understand why it matters. Add context instead of adding more ALL-CAPS emphasis.

### Step 4: Re-test

Run the test prompts again after changes. Check that:
- The original problem is fixed
- No regressions on other test cases
- The skill still triggers correctly

---

## Skill Quality Checklist

Before declaring a skill done:

- [ ] **Description triggers correctly** — covers real user phrases, doesn't over-trigger
- [ ] **Instructions are actionable** — imperative form, clear steps, no ambiguity
- [ ] **Examples included** — at least one input/output example for key operations
- [ ] **Output format defined** — explicit template if the output has structure
- [ ] **Under 500 lines** — large content moved to `references/` subdirectory
- [ ] **No duplication** — doesn't overlap with existing skills
- [ ] **Edge cases handled** — instructions cover the common failure modes
- [ ] **Tested with 2-3 prompts** — confirmed it triggers and produces correct output
- [ ] **Registered** — added to copilot-instructions.md skill list

---

## Patterns from Experience

### What Makes Skills Work Well

1. **Specific trigger words** in the description beat generic descriptions every time
2. **Scripts bundled in the skill** save the model from reinventing wheels — if you see the model writing the same helper code repeatedly, add it to the skill
3. **Step-by-step workflows** with numbered steps are followed more reliably than prose paragraphs
4. **"Do NOT" guards** for common mistakes are effective (e.g., "Do NOT use `$mail.Send()` — always use `$mail.Display()`")
5. **Real file paths** in the skill body (not placeholders) prevent the model from guessing wrong paths

### What Makes Skills Fail

1. **Vague instructions** like "process appropriately" — the model will invent its own approach
2. **Too many options** without clear selection logic — the model gets paralyzed
3. **Outdated information** — paths, APIs, or commands that have changed
4. **Missing context** — assuming the model knows project-specific details it doesn't
5. **Overly rigid structure** — forcing exact formats when flexibility would produce better results

---

## Related Skill: `agent-customization`

VS Code Copilot also ships a meta-skill called `agent-customization` at
`c:\Users\asalmon\.vscode\extensions\github.copilot-chat-*\assets\prompts\skills\agent-customization\SKILL.md`.

That one covers:
- `.instructions.md` / `.prompt.md` / `.agent.md` files
- YAML frontmatter syntax and `applyTo` patterns
- Tool restrictions for specialized agent modes
- Debugging "why isn't my instruction being followed?"

Use `skill-creator` (this skill) when capturing **workflows** as reusable knowledge.
Use `agent-customization` when configuring **how Copilot itself behaves** in this workspace.
