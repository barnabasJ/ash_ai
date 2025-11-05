# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.Server do
  @moduledoc """
  Implementation of the Model Context Protocol (MCP) server using Hermes MCP.

  This module handles MCP requests according to the MCP specification,
  integrating with the AshAi tool system to provide AI-assisted operations.
  """

  use Hermes.Server,
    name: "AshAi MCP Server",
    version: "0.3.0"

  @doc """
  Initialize the MCP server and register tools.

  This callback is invoked when the MCP client sends an initialize request.
  We use this to set up our tools based on the provided options.
  """
  @impl true
  def init(protocol_options, opts) do
    # Store opts for later use in handle_tool
    state = %{
      opts: opts,
      protocol_options: protocol_options
    }

    {:ok, state}
  end

  @doc """
  List available tools for the MCP client.

  This callback is invoked when the client requests the list of available tools.
  """
  @impl true
  def handle_list_tools(state) do
    tools = get_tools(state.opts)

    tool_specs =
      Enum.map(tools, fn tool ->
        %{
          name: tool.name,
          description: tool.description,
          inputSchema: tool.parameters_schema
        }
      end)

    {:reply, tool_specs, state}
  end

  @doc """
  Handle tool execution requests.

  This callback is invoked when the client requests to execute a specific tool.
  """
  @impl true
  def handle_call_tool(tool_name, arguments, state) do
    opts = state.opts

    # Get actor, tenant, and context from opts
    actor = opts[:actor]
    tenant = opts[:tenant]
    context = opts[:context] || %{}

    # Find the tool
    tools = get_tools(opts)

    case Enum.find(tools, &(&1.name == tool_name)) do
      nil ->
        {:error, %{code: -32602, message: "Tool not found: #{tool_name}"}, state}

      tool ->
        # Build context for tool execution
        tool_context = %{
          actor: actor,
          tenant: tenant,
          context: Map.put(context, :otp_app, opts[:otp_app])
        }

        # Execute the tool
        case tool.function.(arguments, tool_context) do
          {:ok, result, _} ->
            {:reply, [%{type: "text", text: result}], state}

          {:error, error} ->
            {:error,
             %{code: -32000, message: "Tool execution failed", data: %{error: inspect(error)}},
             state}
        end
    end
  end

  @doc """
  Get the list of tools based on options.
  """
  defp get_tools(opts) do
    opts =
      if opts[:tools] == :ash_dev_tools do
        opts
        |> Keyword.put(:actions, [{AshAi.DevTools.Tools, :*}])
        |> Keyword.put(:tools, [
          :list_ash_resources,
          :list_generators,
          :get_usage_rules,
          :list_packages_with_rules
        ])
      else
        opts
      end

    opts
    |> Keyword.take([:otp_app, :tools, :actor, :context, :tenant, :actions])
    |> Keyword.update(
      :context,
      %{otp_app: opts[:otp_app]},
      &Map.put(&1, :otp_app, opts[:otp_app])
    )
    |> Keyword.put(:filter, fn tool -> tool.mcp == :tool end)
    |> AshAi.functions()
  end
end
