# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.HermesServer do
  @moduledoc """
  Hermes.Server implementation for AshAi MCP integration.

  This module implements the Hermes.Server behavior to provide MCP protocol
  support for AshAi tools. It bridges the AshAi tool DSL with Hermes'
  component-based architecture through runtime tool registration.

  ## Architecture

  The server dynamically registers tools at initialization time based on:
  - The `:domains` option specifying which Ash domains provide tools
  - The `:tools` option filtering which tools to expose
  - The `:tool_filter` option for additional filtering logic

  Tools are extracted via `AshAi.Info.tools/1` and transformed to Hermes
  format using `AshAi.Mcp.ToolBridge`.

  ## Usage

  This server is typically started via the router configuration:

      forward "/mcp", AshAi.Mcp.Router,
        domains: [MyApp.Blog],
        tools: [:list_posts, :create_post],
        otp_app: :my_app

  The router delegates to this server for actual MCP protocol handling.
  """

  use Hermes.Server,
    name: "AshAi MCP Server",
    version: "0.3.0",
    capabilities: [:tools]

  @doc """
  Initializes the server with client information.

  This callback is invoked during the MCP handshake when a client connects.
  It receives the client's information and the current frame.

  In future tasks, this will be extended to:
  - Extract tools from the provided domains
  - Register tools with Hermes for MCP protocol exposure
  - Apply tool filtering according to options

  ## Options (passed via frame.private)

    * `:domains` - List of Ash domains that provide tools (required)
    * `:tools` - List of tool names to expose, or `:all` (optional)
    * `:tool_filter` - Additional filter function for tools (optional)
    * `:protocol_version` - MCP protocol version (optional, defaults to "2025-03-26")
    * `:otp_app` - OTP application name (optional)

  ## Returns

    * `{:ok, frame}` on successful initialization

  The frame returned will have all requested tools registered and ready for
  MCP protocol operations.
  """
  @impl true
  def init(_client_info, frame) do
    # Server info is handled by Hermes.Server automatically
    # based on the `use Hermes.Server` options above
    #
    # Tool registration will be implemented in upcoming tasks after
    # ToolBridge and ContextMapper modules are created
    {:ok, frame}
  end

  @doc """
  Handles tool execution requests from MCP clients.

  This callback is invoked when a client calls a tool via the `tools/call`
  MCP method. It extracts the auth context from the frame, executes the tool,
  and formats the response according to MCP protocol requirements.

  ## Parameters

    * `name` - The name of the tool to execute
    * `arguments` - The tool arguments provided by the client
    * `frame` - The current frame containing session and auth context

  ## Returns

    * `{:reply, result, frame}` on successful execution
    * `{:error, error, frame}` on execution failure

  The result is formatted as MCP content with appropriate type information.
  """
  @impl true
  def handle_tool_call(_name, _arguments, frame) do
    # Full implementation will be added in Task 6 after ToolBridge
    # and ContextMapper modules are available
    {:reply, %{content: [%{type: "text", text: "Not yet implemented"}]}, frame}
  end
end
