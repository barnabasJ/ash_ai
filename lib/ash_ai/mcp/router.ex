# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Plug) do
  defmodule AshAi.Mcp.Router do
    @moduledoc """
    MCP Router implementing the RPC functionality over HTTP.

    **Note**: This module is a backward compatibility wrapper around `AshAi.Mcp.Plug`.
    New applications should use `AshAi.Mcp.Plug` directly.

    This router handles HTTP requests according to the Model Context Protocol specification
    using the Hermes MCP SDK.

    ## Usage

    ```elixir
    forward "/mcp", AshAi.Mcp.Router, tools: [:tool1, :tool2], otp_app: :my_app
    ```

    ## Migration to v0.4.0

    The router now uses Hermes MCP SDK internally for better protocol compliance.
    The public API remains unchanged, but internally it delegates to `AshAi.Mcp.Plug`
    which uses `Hermes.Server.Transport.StreamableHTTP.Plug`.

    For new projects, consider using `AshAi.Mcp.Plug` directly:

    ```elixir
    forward "/mcp", AshAi.Mcp.Plug,
      domains: [MyApp.Domain],
      tools: [:tool1, :tool2],
      otp_app: :my_app
    ```
    """

    @behaviour Plug

    @doc """
    Initializes the router by delegating to AshAi.Mcp.Plug.

    This maintains backward compatibility while using the new Hermes-based implementation.
    """
    @impl true
    defdelegate init(opts), to: AshAi.Mcp.Plug

    @doc """
    Handles HTTP requests by delegating to AshAi.Mcp.Plug.

    This maintains backward compatibility while using the new Hermes-based implementation.
    """
    @impl true
    defdelegate call(conn, opts), to: AshAi.Mcp.Plug
  end
end
