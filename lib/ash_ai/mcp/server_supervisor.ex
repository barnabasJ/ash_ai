# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ServerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing HermesServer instances.

  This supervisor manages dynamically started MCP server processes,
  allowing multiple server configurations to coexist with proper supervision.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new HermesServer under supervision with the given name and options.

  Uses Hermes.Server's child_spec which starts the server via Hermes.Server.Supervisor.
  """
  def start_server(server_name, opts) do
    # Add server name and transport to opts
    # Use streamable_http without a port - the Plug handles HTTP transport
    opts_with_name =
      opts
      |> Keyword.put(:name, server_name)
      |> Keyword.put(:transport, {:streamable_http, []})

    # Get the child_spec from HermesServer (provided by `use Hermes.Server`)
    # Override the id to be the server_name for uniqueness
    child_spec =
      AshAi.Mcp.HermesServer.child_spec(opts_with_name)
      |> Map.put(:id, server_name)
      |> Map.put(:restart, :transient)

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      :ignore -> {:error, :server_init_ignored}
      error -> error
    end
  end
end
