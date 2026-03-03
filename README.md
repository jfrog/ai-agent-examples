# JFrog AI Agent Examples

A curated collection of AI agent skills examples for automating workflows on the JFrog Platform. Each skill is a self-contained module that an AI coding assistant (such as Cursor) can follow to accomplish domain-specific tasks through natural-language conversation.

## Available Skills

| Skill | Description |
|---|---|
| [Evidence Compliance Policies](evidence-compliance-policies/) | Create lifecycle policies that validate evidence exists before allowing application promotion through release stages |

## Repository Structure

```
ai-agent-examples/
├── global/                          # Shared rules applied across all skills
│   └── rules/
├── <skill-name>/                    # One directory per skill
│   ├── README.md                    # Human-facing overview and usage guide
│   └── skills/
│       ├── SKILL.md                 # Agent-facing instructions (the skill definition)
│       ├── rules/                   # Cursor rules scoped to this skill
│       └── assets/                  # Reference files, schemas, examples
├── .env.example                     # Template for required environment variables
└── NOTICE                           # License information
```

When adding a new skill, create a directory at the repo root following the layout above. Place the `SKILL.md` that the agent executes under `skills/`, and any supporting assets or rules alongside.

## Getting Started

### Prerequisites

- A JFrog Platform instance (specific entitlements depend on the skill)
- An access token with the privileges required by the skill you want to use
- `curl` and `jq` installed locally

### Configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your JFrog Platform URL and access token. The file should be git-ignored to prevent accidental credential exposure.

### Using a Skill

Depending on our AI tool, Cursor (or another AI-assisted IDE that supports agent skills) 
1. Copy the skill conrtent into the appropreate location, for cursor for example, copy all the content under the skill folder under .cursor/skills and all global/rules under .cursor/rules.
2. Ask the agent to perform the task in natural language. For example:

   > "Create a promotion policy that requires SLSA provenance evidence"

The agent will follow the skill's workflow, authenticate with your JFrog Platform, and walk you through each step interactively.

## Contributing

We welcome contributions of new skills and improvements to existing ones. When contributing a new skill, please:

1. Follow the repository structure described above.
2. Include a `README.md` with prerequisites, supported use cases, and example prompts.
3. Include a `SKILL.md` with clear, step-by-step agent instructions.
4. Add reference assets under `assets/` where applicable.
5. Keep shared conventions in `global/rules/` and skill-specific ones in `<skill-name>/skills/rules/`.

## License

This project is licensed under the Apache License 2.0 — see the [NOTICE](NOTICE) file for details.
