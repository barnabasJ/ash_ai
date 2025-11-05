# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.Dev do
  @moduledoc """
  Place in your endpoint's code_reloading section to expose Ash dev MCP"

  Default path is `/ash_ai/mcp`
  """
  @behaviour Plug

  @impl true
  def init(opts) do
    path =
      opts
      |> Keyword.get(:path, "/ash_ai/mcp")
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))

    opts =
      opts
      |> Keyword.put(:tools, :ash_dev_tools)
      |> Keyword.put(:path, path)

    AshAi.Mcp.Router.init(opts)
  end

  @impl true
  def call(%Plug.Conn{path_info: path_info} = conn, opts) do
    expected_path = Keyword.get(opts, :path)

    case Enum.split(path_info, length(expected_path)) do
      {^expected_path, _rest} ->
        # Forward to the router with tools set to ash_dev_tools
        AshAi.Mcp.Router.call(conn, opts)

      _ ->
        conn
    end
  end
end
