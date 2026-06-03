# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deep Blue is a Phoenix v1.8+ LiveView web application that provides an AI chat interface. The app uses an **agentic system** (`lib/agentic/`) built with GenServers and state machines to manage LLM conversations with support for tool calling and streaming responses.

Key dependencies: `req_llm` for LLM interactions, `zoi` for UI components, `req` for HTTP requests.

## Common Commands

```bash
# Initial setup (installs deps, creates DB, runs migrations, seeds, builds assets)
mix setup

# Start Phoenix server (with LiveReload)
mix phx.server

# Start in IEx for interactive debugging
iex -S mix phx.server

# Run all tests (DB setup included)
mix test

# Run a specific test file
mix test test/my_test.exs

# Run only previously failed tests
mix test --failed

# Pre-commit checks (compile with warnings-as-errors, check unused deps, format, test)
mix precommit

# Database operations
mix ecto.create
mix ecto.migrate
mix ecto.reset  # drop + create + migrate + seed
mix ecto.gen.migration migration_name_using_underscores

# Assets
mix assets.setup   # install tailwind + esbuild
mix assets.build   # compile + build assets
mix assets.deploy  # minify assets for production
```

## Agentic System Architecture

The agentic system in `lib/agentic/` is a state machine-based agent framework:

- **Agentic.Server** - GenServer that orchestrates conversation turns. Uses `Registry` for name registration (`Agentic.Registry`). Each agent instance gets a unique ID.
- **Agentic.Core.Loop** - State machine managing conversation flow (idle → calling_llm → calling_tools → idle). Handles both streaming and non-streaming LLM calls.
- **Agentic.Core.Command** - Command objects for side effects (`:call_llm`, `:call_llm_stream`, `:exec_tool`, `:end_turn`)
- **Agentic.LLM** - Thin wrapper around `ReqLLM` for text generation. Model IDs use `provider:model` syntax (e.g., `"zai_coding_plan:glm-4.7"`)
- **Agentic.LLMDBLoader** - Transient GenServer that loads model data into ETS table `:llm_db` on startup, then terminates

The application starts these processes: `Telemetry`, `Repo`, `DNSCluster`, `PubSub`, `Agentic.Registry`, `Agentic.LLMDBLoader`, `Endpoint`.

## Phoenix v1.8+ Requirements

**CRITICAL**: All authenticated LiveViews must use `current_scope` pattern:
- Begin templates with `<Layouts.app flash={@flash} current_scope={@current_scope}>`
- Routes must be in proper `live_session` blocks
- `<.flash_group>` is forbidden outside `layouts.ex`

**Forms**: Use `to_form/2` in LiveView, access via `@form[:field]` in templates. Never pass changesets directly to `<.form>`.

**LiveView streams** (required for collections): Use `stream/3` for lists, set `phx-update="stream"` on parent, consume `@streams.name` with `id={id}` on children. Re-stream items when updating assigns that affect rendered content.

**UI Components**:
- Use `<.icon name="hero-x-mark">` from `core_components.ex` (never Heroicons modules)
- Use `<.input field={@form[:field]}>` for form inputs
- Tailwind CSS v4 via `@import "tailwindcss" source(none);` in `app.css` - no `@apply`
- No inline `<script>` tags - use colocated JS hooks (`:type={Phoenix.LiveView.ColocatedHook}`)

## Language-Specific Notes

**Elixir**: Lists don't support index access via `mylist[i]` - use `Enum.at/2` or pattern matching. Rebind expressions: `socket = if connected?(socket), do: assign(...)` (not rebinding inside the `if`). Never nest multiple modules in the same file.

**HTTP**: Use `Req` (included) - avoid `:httpoison`, `:tesla`, `:httpc`.

**Ecto**: Preload associations before template access. Use `Ecto.Changeset.get_field/2` for changeset fields. Programmatically set fields (e.g., `user_id`) must NOT be in `cast` calls.
