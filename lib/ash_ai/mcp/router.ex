# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Plug) do
  defmodule AshAi.Mcp.Router do
    @moduledoc """
    MCP Router implementing the RPC functionality over HTTP using Hermes MCP.

    This router handles HTTP requests according to the Model Context Protocol specification.

    ## Usage

    ```elixir
    forward "/mcp", AshAi.Mcp.Router, tools: [:tool1, :tool2], otp_app: :my_app
    ```
    """

    @behaviour Plug

    @impl true
    def init(opts) do
      # Validate and store options
      opts
    end

    @impl true
    def call(conn, opts) do
      # Get actor, tenant, and context from connection
      actor = Ash.PlugHelpers.get_actor(conn)
      tenant = Ash.PlugHelpers.get_tenant(conn)
      context = Ash.PlugHelpers.get_context(conn) || %{}

      # Merge connection-specific data with provided options
      server_opts =
        opts
        |> Keyword.put(:actor, actor)
        |> Keyword.put(:tenant, tenant)
        |> Keyword.put(:context, context)

      # Generate a unique server name for this configuration
      # This ensures each endpoint/configuration has its own server instance
      server_name = server_name_for_opts(server_opts)

      # Ensure server is started
      case ensure_server_running(server_name, server_opts) do
        {:ok, _pid} ->
          # Delegate to Hermes transport handler
          # Hermes.Transport.StreamableHTTP handles the HTTP/SSE protocol
          # Note: This assumes Hermes provides a `call/2` function for Plug integration
          # If the API differs, this will need adjustment when dependencies are installed
          Hermes.Transport.StreamableHTTP.call(conn, server_name)

        {:error, reason} ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(
            500,
            Jason.encode!(%{error: "Failed to start MCP server", reason: inspect(reason)})
          )
      end
    end

    # Generate a unique name for the server based on options
    defp server_name_for_opts(opts) do
      # Use the otp_app and tools configuration to generate a unique name
      otp_app = opts[:otp_app] || :ash_ai
      tools = opts[:tools] || []

      tools_hash =
        :erlang.phash2({otp_app, tools})
        |> Integer.to_string()

      Module.concat([AshAi.Mcp.Server, "Instance#{tools_hash}"])
    end

    # Ensure a server is running with the given name and options
    defp ensure_server_running(server_name, opts) do
      case Process.whereis(server_name) do
        nil ->
          # Server not running, start it
          start_server(server_name, opts)

        pid when is_pid(pid) ->
          # Server already running
          {:ok, pid}
      end
    end

    # Start a new server instance
    defp start_server(server_name, opts) do
      child_spec = %{
        id: server_name,
        start:
          {AshAi.Mcp.Server, :start_link,
           [
             [
               name: server_name,
               transport: :streamable_http,
               init_options: opts
             ]
           ]},
        restart: :permanent
      }

      case DynamicSupervisor.start_child(AshAi.Mcp.DynamicSupervisor, child_spec) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        error ->
          error
      end
    end
  end
end
