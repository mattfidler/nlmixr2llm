# nlmixr2llm 0.1.0

* Initial version.
* Ships a single combined `nlmixr2verse` agent spanning the nlmixr2
  pharmacometrics ecosystem (`rxode2`, `nlmixr2`, `nonmem2rx`, `monolix2rx`,
  `babelmixr2`), plus one skill per package.
* Accessor functions: `list_packages()`, `list_agents()`, `list_skills()`,
  `get_agent()`, `get_skill()`, and `system_prompt()` for use as a system
  prompt with any LLM client.
* Installer functions write the content into the locations expected by Claude
  Code (`install_claude_code()`), OpenAI Codex CLI (`install_codex()`),
  Positron Assistant (`install_positron()`), and any tool that reads
  `AGENTS.md` (`install_agents_md()`). Multi-file installers track what they
  write in a manifest and can prune content the package no longer ships.
* `nlmixr2llm_status()` reports whether the content installed into each target
  is up to date with the package.
