# Livellm

Livellm is a Phoenix app that acts as a minimal Open WebUI-style chat client for `llm_composer`. It lets you save provider credentials, start chats against different providers and models, toggle streaming, choose a reasoning effort when supported, and inspect token and cost metadata captured from responses.

This repo is primarily a showcase of how to build a thin product-style UI around [`llm_composer`](https://github.com/doofinder/llm_composer), not a full replacement for Open WebUI.

## Why This Repo Exists

`llm_composer` is the reusable Elixir library that talks to model providers and normalizes their responses. Livellm is a concrete reference app that shows how to wire that library into a Phoenix LiveView UI with persisted chats, provider configuration, streaming updates, and usage tracking.

References:

- Upstream library: https://github.com/doofinder/llm_composer
- Local reference copy: [`./llm_composer`](/home/johanderson/work/sandbox/proyectos/livellm/llm_composer)

## What It Demonstrates From `llm_composer`

Livellm currently exercises these `llm_composer` capabilities:

- Multi-provider chat execution behind one UI flow
- Streaming responses rendered incrementally in LiveView
- Reasoning output capture and display when returned by the provider/model
- Reasoning-effort passthrough for providers that support it
- Normalized token and cost tracking across providers
- OpenAI Responses API conversation continuity via previous response IDs
- Provider-specific request shaping such as prompt caching hooks
- Persisting normalized assistant metadata back into chat history

This app intentionally focuses on the integration story. For the full library surface, provider docs, and advanced features, use the upstream `llm_composer` README.

## Supported Providers In This App

| Provider | Credentials needed | Base URL override | Reasoning effort UI | Streaming toggle | Notes |
| --- | --- | --- | --- | --- | --- |
| `openai` | API key | Yes | Exposed in UI, not forwarded by this app | Yes | Uses OpenAI Chat Completions via `llm_composer` |
| `openai_responses` | API key | Yes | Yes | Yes | Supports previous response ID reuse and prompt cache key |
| `openrouter` | API key | Yes | Yes | Yes | Reasoning is forwarded through provider-specific request params |
| `ollama` | Usually none or local token | Yes | Exposed in UI, not forwarded by this app | Yes | Intended for local/self-hosted Ollama endpoints |
| `google` | API key | Yes | Exposed in UI, not forwarded by this app | Yes | This app documents API-key-based usage, not Vertex AI setup |

Notes:

- Model names are entered manually.
- Capability support still depends on the selected model and provider behavior.
- The UI always shows reasoning controls, but only `openai_responses` and `openrouter` currently receive reasoning-effort options from this app.

## Local Setup

Prerequisites:

- Elixir and Erlang compatible with this project
- A working local development environment for Phoenix

Setup and run:

```bash
mix setup
mix phx.server
```

Then open http://localhost:4000

`mix setup` installs dependencies, creates the local SQLite database, runs migrations, seeds the database, and builds assets.

## How To Use Livellm

1. Open `Settings`.
2. Add a provider configuration with:
   - provider type
   - label
   - API key if required
   - optional default model
   - optional base URL override
3. Mark one provider config as active.
4. Start a new chat.
5. Choose the provider, model, reasoning effort, and streaming mode from the chat header.
6. Send messages and inspect the response stream, reasoning panel, and token/cost badges in the header.

Behavior details:

- Chats are persisted in the local database.
- Assistant messages store normalized metadata such as provider name, provider model, token counts, cached tokens, reasoning tokens, cost, and provider response IDs when available.
- Per-chat UI settings for provider/model/reasoning/streaming are restored from browser `localStorage`.

## Example Configurations

### OpenAI Responses

- Provider: `openai_responses`
- Default model: `gpt-5.4-mini`
- API key: your OpenAI key
- Streaming: enabled
- Reasoning effort: `low`, `medium`, `high`, or another supported value

This is the most complete showcase path in the app because it supports streaming, reasoning-effort passthrough, previous response ID reuse, and prompt cache keys.

### OpenRouter

- Provider: `openrouter`
- Default model: a provider-qualified model such as `anthropic/claude-...` or another OpenRouter model
- API key: your OpenRouter key
- Optional base URL: custom gateway if needed
- Streaming: enabled

Livellm forwards reasoning settings to OpenRouter through provider-specific request params when selected.

### Ollama

- Provider: `ollama`
- Default model: local model name such as `llama3.1`
- Base URL: usually `http://localhost:11434`
- API key: optional depending on your deployment

This is the local/self-hosted path for testing the same UI against an Ollama instance.

## How The App Is Wired

The main integration points are:

- [`lib/livellm_web/live/settings_live.ex`](/home/johanderson/work/sandbox/proyectos/livellm/lib/livellm_web/live/settings_live.ex): provider config CRUD and active-provider selection
- [`lib/livellm_web/live/chat_live.ex`](/home/johanderson/work/sandbox/proyectos/livellm/lib/livellm_web/live/chat_live.ex): chat UX, streaming updates, persisted conversation flow, and metrics display
- [`lib/livellm/chats/llm_runner.ex`](/home/johanderson/work/sandbox/proyectos/livellm/lib/livellm/chats/llm_runner.ex): provider dispatch, request option shaping, reasoning-effort forwarding, cache hints, and OpenAI Responses continuity

At a high level:

- provider configs are stored locally
- chat messages are persisted in SQLite
- LiveView drives the UI and streams message updates
- `llm_composer` handles provider calls and normalized response parsing

## Current Limitations

Livellm is intentionally minimal.

- It is not a full Open WebUI replacement.
- There is no authentication or multi-user isolation.
- Provider credentials are stored locally in the app database.
- Chats and response metadata are stored locally in the app database.
- Model capability detection is manual, so unsupported provider/model/option combinations can fail at runtime.
- The reasoning selector is visible for all providers even though only some providers currently use it.
- This README documents the app integration, not every `llm_composer` feature.

## Development

Useful commands:

```bash
mix test
mix precommit
```

Use `mix precommit` before finalizing changes. It compiles with warnings as errors, formats code, runs Credo, and runs the test suite.

## Reference

For full `llm_composer` documentation, provider coverage, and advanced usage patterns, go to:

- https://github.com/doofinder/llm_composer
- [`./llm_composer/README.md`](/home/johanderson/work/sandbox/proyectos/livellm/llm_composer/README.md)

Livellm should be read as the companion example app showing how those capabilities can be surfaced in a minimal Phoenix LiveView product.
