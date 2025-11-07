# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ContextMapper do
  @moduledoc """
  Maps authentication context between Plug.Conn and Hermes.Server.Frame.

  This module provides bidirectional transformation of authentication and
  authorization context between Phoenix/Plug's `conn` structure and Hermes
  MCP server's `frame` structure.

  ## Context Flow

  ### Plug → Frame (to_frame/2)

  When an HTTP request arrives at the MCP endpoint, authentication context
  is extracted from the Plug.Conn and stored in the Hermes frame assigns:

  - `actor` - The authenticated user/actor (via Ash.PlugHelpers.get_actor/1)
  - `tenant` - Multi-tenancy tenant ID (via Ash.PlugHelpers.get_tenant/1)
  - `context` - Additional context map (via Ash.PlugHelpers.get_context/1)

  ### Frame → Keyword List (from_frame/1)

  When executing tools within Hermes, the context is extracted from the
  frame and converted to a keyword list compatible with Ash action execution:

      [actor: actor, tenant: tenant, context: context]

  ## Usage

  ### In Router (HTTP Request → Frame)

      def call(conn, opts) do
        # Extract auth context from conn
        frame = ContextMapper.to_frame(conn, initial_frame)
        # ... pass frame to Hermes transport
      end

  ### In Tool Execution (Frame → Keyword List)

      def handle_tool_call(name, arguments, frame) do
        # Extract context for Ash action
        opts = ContextMapper.from_frame(frame)
        # Execute tool with context
        MyDomain.execute_tool(name, arguments, opts)
      end

  ## Compatibility

  This module maintains compatibility with the existing auth pattern from
  `lib/ash_ai/mcp/server.ex:25-28` which uses Ash.PlugHelpers to extract
  context from conn.private.
  """

  alias Hermes.Server.Frame

  @doc """
  Extracts authentication context from Plug.Conn and assigns to Hermes frame.

  Uses Ash.PlugHelpers to extract actor, tenant, and context from the conn's
  private storage, then assigns them to the frame using Frame.assign/3.

  ## Parameters

    * `conn` - Plug.Conn containing authentication context in conn.private
    * `frame` - Hermes.Server.Frame to store the context in

  ## Returns

  Updated frame with auth context in frame.assigns:
    * `:actor` - Authenticated actor (or nil)
    * `:tenant` - Tenant identifier (or nil)
    * `:context` - Additional context map (defaults to %{})

  ## Examples

      iex> conn = %Plug.Conn{private: %{ash_actor: %{id: 123}}}
      iex> frame = %Frame{assigns: %{}}
      iex> frame = ContextMapper.to_frame(conn, frame)
      iex> frame.assigns.actor
      %{id: 123}

  """
  @spec to_frame(Plug.Conn.t(), Frame.t()) :: Frame.t()
  def to_frame(conn, frame) do
    # Extract actor, tenant, and context from conn using Ash.PlugHelpers
    # Pattern from lib/ash_ai/mcp/server.ex:25-28
    actor = Ash.PlugHelpers.get_actor(conn)
    tenant = Ash.PlugHelpers.get_tenant(conn)
    context = Ash.PlugHelpers.get_context(conn) || %{}

    # Assign all three to frame using Frame.assign/3
    frame
    |> Frame.assign(:actor, actor)
    |> Frame.assign(:tenant, tenant)
    |> Frame.assign(:context, context)
  end

  @doc """
  Extracts authentication context from Hermes frame to keyword list.

  Retrieves actor, tenant, and context from frame.assigns and returns them
  in a keyword list format suitable for passing to Ash actions.

  ## Parameters

    * `frame` - Hermes.Server.Frame containing auth context in assigns

  ## Returns

  Keyword list with auth context:
    * `:actor` - Authenticated actor (or nil)
    * `:tenant` - Tenant identifier (or nil)
    * `:context` - Additional context map (defaults to %{})

  ## Examples

      iex> frame = %Frame{assigns: %{actor: %{id: 123}, tenant: "org_1"}}
      iex> ContextMapper.from_frame(frame)
      [actor: %{id: 123}, tenant: "org_1", context: %{}]

  """
  @spec from_frame(Frame.t()) :: Keyword.t()
  def from_frame(frame) do
    # Extract assigns from frame
    assigns = frame.assigns

    # Build keyword list with auth context
    # Default context to %{} if missing (matching server.ex:27)
    [
      actor: Map.get(assigns, :actor),
      tenant: Map.get(assigns, :tenant),
      context: Map.get(assigns, :context, %{})
    ]
  end
end
