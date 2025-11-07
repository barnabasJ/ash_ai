# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Plug) do
  defmodule AshAi.Mcp.Plug do
    @moduledoc """
    Plug for integrating AshAi MCP servers with Phoenix/Plug applications using Hermes.

    This is a thin wrapper around `Hermes.Server.Transport.StreamableHTTP.Plug` that
    configures the AshAi MCP server with domain-specific settings via conn.assigns.

    ## Usage

    In your Phoenix router:

    ```elixir
    forward "/mcp", AshAi.Mcp.Plug,
      domains: [MyApp.Blog],
      tools: [:list_posts, :create_post],
      otp_app: :my_app
    ```

    ## Endpoints

    - `GET /` - Establishes SSE connection
    - `POST /` - Sends MCP protocol messages
    - `DELETE /` - Closes session

    ## Breaking Changes from v0.3.x

    - Session management via Hermes GenServers (more robust)
    - Configuration passed via Plug.Conn.assigns instead of custom routing

    See the v0.4.0 migration guide for details.
    """

    @behaviour Plug

    import Plug.Conn

    @doc """
    Initializes the plug with AshAi configuration and Hermes transport options.
    """
    def init(opts) do
      # Extract AshAi-specific configuration
      ash_ai_opts = %{
        domains: Keyword.get(opts, :domains, []),
        tools: Keyword.get(opts, :tools, :all),
        tool_filter: Keyword.get(opts, :tool_filter),
        otp_app: Keyword.get(opts, :otp_app),
        components: Keyword.get(opts, :components, [])
      }

      # Initialize Hermes Plug with server reference
      hermes_opts = Hermes.Server.Transport.StreamableHTTP.Plug.init(server: AshAi.Mcp.HermesServer)

      # Return both configurations
      {ash_ai_opts, hermes_opts}
    end

    @doc """
    Handles HTTP requests by injecting configuration into assigns and forwarding to Hermes transport.
    """
    def call(conn, {ash_ai_opts, hermes_opts}) do
      # Inject AshAi configuration into conn.assigns
      # This will be available in HermesServer via frame.assigns
      conn
      |> assign(:ash_ai_mcp_config, ash_ai_opts)
      |> Hermes.Server.Transport.StreamableHTTP.Plug.call(hermes_opts)
    end
  end
end
