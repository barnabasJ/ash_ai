# Migrating to Hermes MCP SDK (v0.4.0)

As of v0.4.0, AshAi uses the [Hermes MCP SDK](https://hex.pm/packages/hermes_mcp) for MCP protocol handling. This migration guide covers what you need to know if you were using the previous custom MCP implementation.

## Why Hermes?

The Hermes MCP SDK provides:
- **Spec-compliant protocol**: Follows MCP specification 2025-03-26
- **Robust SSE support**: Better Server-Sent Events handling
- **Session management**: Built-in session lifecycle and cleanup
- **Industry standard**: Aligns with the broader Elixir/MCP ecosystem

## What Changed

### Internal Implementation Only

**Good news**: For most users, the migration is transparent. The public API (`AshAi.Mcp.Router`, `AshAi.Mcp.Dev`) remains the same.

The changes are primarily internal:
- MCP protocol handling delegated to Hermes
- Tool registration uses Hermes Frame API
- Transport layer managed by Hermes

### Configuration (Test Environments)

If you're running tests that interact with MCP, you need to enable the Hermes transport:

```elixir
# config/test.exs
config :ash_ai, :mcp_transport, start: true
```

This is required because Hermes only starts the transport when it detects an HTTP server running. In test environments without Phoenix running, you must explicitly enable it.

## Migration Checklist

### For Production Apps

- [ ] No changes required if using `AshAi.Mcp.Router` or `AshAi.Mcp.Dev`
- [ ] Update dependencies: `mix deps.update ash_ai`
- [ ] Verify MCP connections still work with your clients

### For Test Suites

- [ ] Add transport configuration to `config/test.exs`:
  ```elixir
  config :ash_ai, :mcp_transport, start: true
  ```
- [ ] Update any direct MCP protocol tests to include proper handshake:
  1. Send `initialize` request
  2. Wait for response
  3. Send `notifications/initialized` notification
  4. Make tool calls
- [ ] Maintain session IDs across requests using `mcp-session-id` header

### For Custom MCP Implementations

If you built custom MCP integrations (not using `AshAi.Mcp.Router`):

- [ ] Review Hermes documentation: https://hexdocs.pm/hermes_mcp
- [ ] Update server modules to use `Hermes.Server` behavior
- [ ] Migrate tool registration to `Hermes.Server.Frame.register_tool/3`
- [ ] Update response formatting to use `Hermes.Server.Response` builders
- [ ] Add `Hermes.Server.Registry` to your supervision tree

## Known Issues & Workarounds

### Schema Validation

Currently, AshAi registers tools with Hermes using empty schemas (`%{}`) because:
- Hermes expects Peri schema format
- AshAi generates JSON Schema format
- Validation still happens during tool execution

This is transparent to users but may be addressed in future versions.

## Getting Help

If you encounter migration issues:

1. Check the [Hermes documentation](https://hexdocs.pm/hermes_mcp)
2. Review the [MCP specification](https://spec.modelcontextprotocol.io)
3. Open an issue on [GitHub](https://github.com/ash-project/ash_ai/issues)

## Rollback

If you need to rollback temporarily:

```elixir
# mix.exs
{:ash_ai, "~> 0.3.0"}
```

However, we recommend migrating to v0.4.0+ for better MCP protocol compliance and future improvements.
