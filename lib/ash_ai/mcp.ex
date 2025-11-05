# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp do
  @moduledoc """
  Model Context Protocol (MCP) implementation for Ash Framework using Hermes MCP.

  This module provides a [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server
  that integrates with Ash Framework, powered by [Hermes MCP](https://hexdocs.pm/hermes_mcp/).

  ## Overview

  This MCP implementation provides:

  * A fully compliant MCP server powered by Hermes MCP SDK
  * Support for both JSON and Server-Sent Events (SSE) responses via Streamable HTTP transport
  * Automatic tool registration from AshAi functions
  * Integration with Ash resources and authentication
  * Production-ready server implementation with supervision

  ## Current Features

  * Protocol-compliant initialization and tool handling
  * Automatic tool discovery from AshAi tool definitions
  * Actor, tenant, and context support from Ash.PlugHelpers
  * Dynamic server instance management
  * Plug-compatible router for easy integration
  * Dev mode support with ash_dev_tools

  ## Future Enhancements

  * OAuth integration with AshAuthentication
  * Resource and prompt support
  * Advanced capabilities (sampling, logging, etc.)

  ## Integration

  ### With Phoenix

  ```elixir
  # In your Phoenix router
  forward "/mcp", AshAi.Mcp.Router

  # With tools enabled
  forward "/mcp", AshAi.Mcp.Router, tools: [:tool1, :tool2]
  ```

  ### With Any Plug-Based Application

  The MCP router is a standard Plug, so it can be integrated into any Plug-based application.
  You are responsible for hosting the Plug however you prefer.
  """
end
