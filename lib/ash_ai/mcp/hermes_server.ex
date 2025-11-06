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

  alias Hermes.Server.Response

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

    # Get configuration from frame assigns (set by AshAi.Mcp.Plug)
    config = frame.assigns[:ash_ai_mcp_config] || %{}

    domains = Map.get(config, :domains, [])
    tool_filter = Map.get(config, :tools)

    # Get Hermes tool definitions from AshAi domains
    hermes_tools = AshAi.Mcp.ToolBridge.to_hermes_tools(domains, tool_filter)

    # Register each tool with Hermes
    # Note: We use %{} for input_schema because ToolBridge generates JSON Schema
    # but Hermes expects Peri format. Tool arguments are validated when executed.
    frame =
      Enum.reduce(hermes_tools, frame, fn tool, acc_frame ->
        Hermes.Server.Frame.register_tool(acc_frame, tool.name, [
          description: tool.description,
          input_schema: %{}
        ])
      end)

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
  def handle_tool_call(name, arguments, frame) do
    # Extract context from frame
    context = AshAi.Mcp.ContextMapper.from_frame(frame)

    # Get configuration from frame assigns (set by AshAi.Mcp.Plug or tests)
    # Support both :ash_ai_mcp_config (from Plug) and :opts (from tests)
    config = frame.assigns[:ash_ai_mcp_config] || frame.assigns[:opts] || %{}

    # Convert config to keyword list if it's a map
    opts = if is_map(config) do
      [
        tools: Map.get(config, :tools, :all),
        tool_filter: Map.get(config, :tool_filter),
        otp_app: Map.get(config, :otp_app)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    else
      # Already a keyword list
      config
    end

    # Merge context into opts
    merged_opts = Keyword.merge(opts, context)

    # Get all tool functions - handle errors gracefully
    case try_get_functions(merged_opts) do
      {:ok, functions} ->
        # Continue with tool execution
        execute_tool_by_name(name, arguments, functions, context, frame)

      {:error, reason} ->
        # Failed to load tools
        error = format_error(-32602, "Failed to load tools: #{reason}")
        {:error, error, frame}
    end
  end

  # Private helper to safely get functions
  defp try_get_functions(opts) do
    try do
      {:ok, AshAi.functions(opts)}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  # Private helper to execute tool by name
  defp execute_tool_by_name(name, arguments, functions, context, frame) do
    # Find the specific tool by name
    case Enum.find(functions, fn func -> to_string(func.name) == to_string(name) end) do
      nil ->
        error = format_error(-32601, "Tool '#{name}' not found")
        {:error, error, frame}

      tool_function ->
        # Execute the tool with arguments and context
        case execute_tool(tool_function, arguments, context) do
          {:ok, result} ->
            # Build Response struct using Hermes builders
            response =
              Response.tool()
              |> Response.text(result)

            {:reply, response, frame}

          {:error, reason} ->
            # Format error for MCP protocol
            error = format_execution_error(reason)
            {:error, error, frame}
        end
    end
  end

  # Private helper functions for tool execution

  defp execute_tool(tool_function, arguments, context) do
    # Handle nil arguments from MCP clients
    arguments = arguments || %{}

    # Execute the LangChain.Function with context
    # The function expects (arguments, context) as parameters
    try do
      result = tool_function.function.(arguments, context)

      # Tool functions return {status, json_string, records} tuple
      # Extract just the JSON string for the MCP response
      case result do
        {:ok, json_string, _records} when is_binary(json_string) ->
          {:ok, json_string}

        {:error, reason} ->
          {:error, reason}

        other ->
          # Fallback for unexpected formats
          {:ok, other}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  defp format_error(code, message) do
    %{
      code: code,
      message: message
    }
  end

  defp format_execution_error(%Ash.Error.Invalid{} = error) do
    # Ash validation error - extract messages
    message = Exception.message(error)

    %{
      code: -32603,
      message: "Tool execution failed: #{message}"
    }
  end

  defp format_execution_error(error) when is_exception(error) do
    # Generic exception
    message = Exception.message(error)

    %{
      code: -32603,
      message: "Tool execution failed: #{message}"
    }
  end

  defp format_execution_error(error) do
    # Unknown error type
    %{
      code: -32603,
      message: "Tool execution failed: #{inspect(error)}"
    }
  end
end
