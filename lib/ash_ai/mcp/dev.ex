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

    # Get OTP app from opts (required for discovering domains)
    otp_app = Keyword.get(opts, :otp_app)

    # Discover domains from application config
    domains =
      if otp_app do
        Application.get_env(otp_app, :ash_domains, [])
      else
        []
      end

    opts =
      opts
      |> Keyword.put(:tools, :ash_dev_tools)
      |> Keyword.put(:domains, domains)
      |> Keyword.put(:components, Keyword.get(opts, :components, []))

    # AshAi.Mcp.Plug.init returns {ash_ai_opts, hermes_opts} tuple
    plug_opts = AshAi.Mcp.Plug.init(opts)

    # Store path alongside plug_opts for routing
    {path, plug_opts}
  end

  @impl true
  def call(%Plug.Conn{path_info: path_info} = conn, {expected_path, plug_opts}) do
    case Enum.split(path_info, length(expected_path)) do
      {^expected_path, rest} ->
        conn
        |> Plug.forward(rest, AshAi.Mcp.Plug, plug_opts)
        |> Plug.Conn.halt()

      _ ->
        conn
    end
  end
end
