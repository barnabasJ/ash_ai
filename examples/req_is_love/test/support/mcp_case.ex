defmodule ReqIsLoveWeb.MCPCase do
  @moduledoc """
  Test helpers for MCP protocol testing.

  Provides utilities for:
  - Building MCP JSON-RPC messages
  - Managing MCP sessions
  - Validating MCP responses

  ## Usage

      use ReqIsLoveWeb.MCPCase, async: false

      test "initialize handshake" do
        session_id = initialize_mcp_session()
        # Use session_id for subsequent requests
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ReqIsLoveWeb.ConnCase
      import ReqIsLoveWeb.MCPCase
      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  @doc """
  Generates a unique session ID for MCP testing.
  """
  def unique_session_id do
    "session_test_#{:rand.uniform(1_000_000)}"
  end

  @doc """
  Builds a properly-configured MCP POST connection with required headers.

  ## Parameters

    * `message` - The MCP message map to encode and send
    * `session_id` - Session ID for the mcp-session-id header

  ## Returns

  A Plug.Conn ready for MCP protocol communication.
  """
  def mcp_post_conn(message, session_id) do
    Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(message))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
    |> Plug.Conn.put_req_header("mcp-session-id", session_id)
  end

  @doc """
  Builds an MCP initialize request message.

  ## Parameters

    * `protocol_version` - MCP protocol version (default: "2024-11-05")

  ## Returns

  A map representing a JSON-RPC 2.0 initialize request.
  """
  def initialize_message(protocol_version \\ "2024-11-05") do
    %{
      jsonrpc: "2.0",
      method: "initialize",
      id: "1",
      params: %{
        protocolVersion: protocol_version,
        capabilities: %{},
        clientInfo: %{name: "test_client", version: "1.0.0"}
      }
    }
  end

  @doc """
  Builds an MCP initialized notification message.
  """
  def initialized_notification do
    %{jsonrpc: "2.0", method: "notifications/initialized"}
  end

  @doc """
  Builds an MCP tools/list request message.

  ## Parameters

    * `id` - Request ID (default: "2")
  """
  def list_tools_message(id \\ "2") do
    %{jsonrpc: "2.0", method: "tools/list", id: id, params: %{}}
  end

  @doc """
  Builds an MCP tools/call request message.

  ## Parameters

    * `tool_name` - Name of the tool to call
    * `arguments` - Tool arguments map (default: %{})
    * `id` - Request ID (default: "3")
  """
  def call_tool_message(tool_name, arguments \\ %{}, id \\ "3") do
    %{
      jsonrpc: "2.0",
      method: "tools/call",
      id: id,
      params: %{name: tool_name, arguments: arguments}
    }
  end

  @doc """
  Initializes an MCP session by performing the initialize handshake.

  This function:
  1. Sends an initialize request
  2. Validates the response
  3. Sends an initialized notification
  4. Returns the session ID for subsequent requests

  ## Parameters

    * `conn_opts` - Options to pass to endpoint call (default: [])

  ## Returns

  The session ID string for use in subsequent MCP requests.
  """
  def initialize_mcp_session(conn_opts \\ []) do
    import ExUnit.Assertions, only: [assert: 1]
    import Plug.Conn, only: [put_req_header: 3]

    session_id = unique_session_id()

    # Initialize
    init_conn =
      Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(initialize_message()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id)

    init_response = ReqIsLoveWeb.Endpoint.call(init_conn, conn_opts)
    assert init_response.status == 200

    # Send initialized notification
    notif_conn =
      Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(initialized_notification()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id)

    notif_response = ReqIsLoveWeb.Endpoint.call(notif_conn, conn_opts)
    # Notifications return 202 Accepted, not 200
    assert notif_response.status == 202

    session_id
  end

  @doc """
  Validates an MCP success response.

  Checks:
  - HTTP status 200
  - JSON-RPC 2.0 structure
  - Presence of result field
  - Absence of error field
  - Matching request ID

  ## Parameters

    * `response` - Plug.Conn response
    * `expected_id` - Expected JSON-RPC request ID

  ## Returns

  The result field from the JSON-RPC response.
  """
  def assert_mcp_success(response, expected_id) do
    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["jsonrpc"] == "2.0"
    assert body["id"] == expected_id
    assert Map.has_key?(body, "result")
    refute Map.has_key?(body, "error")
    body["result"]
  end

  @doc """
  Validates an MCP error response.

  Checks:
  - HTTP status 200
  - JSON-RPC 2.0 structure
  - Presence of error field
  - Optional error code matching

  ## Parameters

    * `response` - Plug.Conn response
    * `expected_code` - Optional expected error code (e.g., -32601)

  ## Returns

  The error field from the JSON-RPC response.
  """
  def assert_mcp_error(response, expected_code \\ nil) do
    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["jsonrpc"] == "2.0"
    assert Map.has_key?(body, "error")

    if expected_code do
      assert body["error"]["code"] == expected_code
    end

    body["error"]
  end
end
