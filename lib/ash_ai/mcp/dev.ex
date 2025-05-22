defmodule AshAi.Mcp.Dev do
  @moduledoc """
  Place in your endpoint's code_reloading section to expose Ash dev MCP"

  Default path is `/mcp/ash`
  """
  @behaviour Plug

  @impl true
  def init(opts) do
    path =
      opts
      |> Keyword.get(:path, "/mcp/ash")
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

    if List.starts_with?(path_info, expected_path) do
      rest = Enum.drop(path_info, length(expected_path))

      conn
      |> Plug.forward(rest, AshAi.Mcp.Router, opts)
      |> Plug.Conn.halt()
    else
      conn
    end
  end
end
