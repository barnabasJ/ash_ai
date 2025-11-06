# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Get MCP transport config (allows forcing transport start in test env)
    transport_opts = Application.get_env(:ash_ai, :mcp_transport, [])

    children = [
      # Registry for Hermes MCP servers
      Hermes.Server.Registry,
      # AshAi MCP Server with streamable_http transport
      # In production: auto-detects when Phoenix is running
      # In test: can be forced via config
      {AshAi.Mcp.HermesServer, transport: {:streamable_http, transport_opts}}
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: AshAi.Supervisor
    )
  end
end
