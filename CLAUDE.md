# Thor AArch64 notes moved into AGENTS.md

Read [`AGENTS.md`](AGENTS.md). It is the operating contract AND the hardware
knowledge, in one file, since 2026-08-23.

This file exists so a tool that looks for `CLAUDE.md` finds the way there.

Do not copy content into this file. Two copies of a map disagree.

The writing standard for all English is in `AGENTS.md`, section `Write
documentation in ASD-STE100`. It applies since 2026-09-17.

The device tools are in `AGENTS.md`, section `The thor MCP server: typed tools
instead of a hand-written harness`. Claude Code loads the `thor` server from
`.mcp.json` when it starts in this directory or in the workspace root. Use its
tools before you write an adb command.
