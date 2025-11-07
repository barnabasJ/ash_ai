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
  alias Hermes.MCP.Error

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
    # Note: We convert JSON Schema to Peri format for Hermes validation
    # Peri will validate the structure, AshAi validates the business logic
    frame =
      Enum.reduce(hermes_tools, frame, fn tool, acc_frame ->
        # Convert JSON Schema to Peri format
        peri_schema = json_schema_to_peri(tool.input_schema)

        Hermes.Server.Frame.register_tool(acc_frame, tool.name, [
          description: tool.description,
          input_schema: peri_schema
        ])
      end)

    {:ok, frame}
  end

  # Convert JSON Schema to Peri schema format
  # Peri uses tuples like {:required, :string} instead of %{"type" => "string"}
  defp json_schema_to_peri(json_schema) when is_map(json_schema) do
    properties = Map.get(json_schema, "properties", %{})
    required = Map.get(json_schema, "required", [])

    Enum.reduce(properties, %{}, fn {key, value}, acc ->
      is_required = key in required
      peri_type = convert_json_type_to_peri(value, is_required)
      Map.put(acc, String.to_atom(key), peri_type)
    end)
  end

  defp json_schema_to_peri(_), do: %{}

  # Convert JSON Schema type definitions to Peri format
  # NOTE: In Peri, fields are optional by default - only required fields use {:required, type}
  defp convert_json_type_to_peri(%{"type" => "object", "properties" => _props} = schema, required?) do
    # Recursively convert nested object properties
    # Peri uses plain maps for nested objects
    nested_schema = json_schema_to_peri(schema)
    if required?, do: {:required, nested_schema}, else: nested_schema
  end

  defp convert_json_type_to_peri(%{"type" => "string"}, required?) do
    if required?, do: {:required, :string}, else: :string
  end

  defp convert_json_type_to_peri(%{"type" => "integer"}, required?) do
    if required?, do: {:required, :integer}, else: :integer
  end

  defp convert_json_type_to_peri(%{"type" => "boolean"}, required?) do
    if required?, do: {:required, :boolean}, else: :boolean
  end

  defp convert_json_type_to_peri(%{"type" => "array"}, required?) do
    if required?, do: {:required, :list}, else: :list
  end

  defp convert_json_type_to_peri(_, required?) do
    # Fallback for unknown types - accept any value
    if required?, do: {:required, :any}, else: :any
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
    # Note: Don't pass :domains - AshAi.functions discovers domains via otp_app config
    # Note: Only pass :tools if it's a list of tool names, not :all or :ash_dev_tools
    opts = if is_map(config) do
      tools_value = Map.get(config, :tools, :all)

      base_opts = [
        tool_filter: Map.get(config, :tool_filter),
        otp_app: Map.get(config, :otp_app)
      ]

      # Only include :tools if it's a list (actual tool names), not :all or :ash_dev_tools
      opts_with_tools =
        if is_list(tools_value) do
          Keyword.put(base_opts, :tools, tools_value)
        else
          base_opts
        end

      Enum.reject(opts_with_tools, fn {_k, v} -> is_nil(v) end)
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
        error = Error.protocol(:invalid_params, %{message: "Failed to load tools: #{reason}"})
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
        error = Error.protocol(:method_not_found, %{message: "Tool '#{name}' not found"})
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
            # Categorize and format error for MCP protocol
            error = categorize_tool_error(reason)
            {:error, error, frame}
        end
    end
  end

  # Private helper functions for tool execution

  defp execute_tool(tool_function, arguments, context) do
    # Handle nil arguments from MCP clients
    arguments = arguments || %{}

    # Convert atom keys to string keys - AshAi functions expect string keys
    arguments = stringify_keys(arguments)

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

  # Helper to recursively convert atom keys to string keys
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  # Categorize tool errors into appropriate MCP error types
  defp categorize_tool_error(error_json) when is_binary(error_json) do
    # Tool errors come back as JSON-encoded error arrays
    # Try to parse and determine if it's a validation error
    case Jason.decode(error_json) do
      {:ok, errors} when is_list(errors) ->
        # Check if this is a validation error (400 status or "required" code)
        is_validation_error = Enum.any?(errors, fn
          %{"status" => "400"} -> true
          %{"code" => "required"} -> true
          %{"title" => "Required"} -> true
          _ -> false
        end)

        if is_validation_error do
          Error.protocol(:invalid_params, %{message: error_json})
        else
          Error.execution("Tool execution failed: #{error_json}")
        end

      _ ->
        # Not parseable JSON or unexpected format
        Error.execution("Tool execution failed: #{error_json}")
    end
  end

  defp categorize_tool_error(%Ash.Error.Invalid{} = error) do
    # Ash validation errors are invalid params (-32602)
    message = Exception.message(error)
    Error.protocol(:invalid_params, %{message: message})
  end

  defp categorize_tool_error(error) when is_exception(error) do
    # Generic exceptions are execution errors (-32000)
    message = Exception.message(error)
    Error.execution("Tool execution failed: #{message}")
  end

  defp categorize_tool_error(error) do
    # Unknown error types are execution errors (-32000)
    Error.execution("Tool execution failed: #{inspect(error)}")
  end
end
