# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Hermes Server Registry for MCP servers
      Hermes.Server.Registry,
      # Dynamic supervisor for MCP server instances
      {DynamicSupervisor, name: AshAi.Mcp.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: AshAi.Supervisor
    )
  end
end
