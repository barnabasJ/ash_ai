defmodule AshAi.Mcp.ToolFilterTest do
  use AshAi.RepoCase, async: false
  import Plug.{Conn, Test}

  alias AshAi.Mcp.Router

  @opts [domains: [AshAi.Test.Music], tools: [:list_artists], otp_app: :ash_ai]

  describe "tool filter bug fix" do
    test "tools/call request works without filter error" do
      # Initialize opts through Router.init to get proper format
      initialized_opts = Router.init(@opts)

      # Use a consistent session ID across requests (provided by client)
      session_id = "session_test_#{:rand.uniform(1000000)}"

      # First initialize a session
      init_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "initialize",
        id: "1",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{},
          clientInfo: %{name: "test_client", version: "1.0.0"}
        }
      })

      init_conn =
        conn(:post, "/", init_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      init_response = Router.call(init_conn, initialized_opts)
      assert init_response.status == 200

      # Send initialized notification to complete handshake
      initialized_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "notifications/initialized"
      })

      initialized_conn =
        conn(:post, "/", initialized_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      initialized_response = Router.call(initialized_conn, initialized_opts)
      assert initialized_response.status == 202

      # Now make a tools/call request
      # This is where the bug happens - the filter tries to access tool.mcp
      call_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "tools/call",
        id: "2",
        params: %{
          name: "list_artists",
          arguments: %{}
        }
      })

      call_conn =
        conn(:post, "/", call_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      # This should work without errors
      # Before fix: Would fail because filter tries to access non-existent tool.mcp field
      call_response = Router.call(call_conn, initialized_opts)

      assert call_response.status == 200
      resp = Jason.decode!(call_response.resp_body)

      # Should either succeed or fail gracefully, but not crash
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "2"

      # Tool should be found (not filtered out by broken filter)
      # If filter was working incorrectly, we'd get "Tool not found" error
      refute Map.has_key?(resp, "error") || resp["error"]["message"] == "Tool not found: list_artists"
    end

    test "tools/list request lists available tools" do
      # Initialize opts through Router.init to get proper format
      initialized_opts = Router.init(@opts)

      # Use a consistent session ID across requests (provided by client)
      session_id = "session_test_#{:rand.uniform(1000000)}"

      # Initialize session
      init_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "initialize",
        id: "1",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{},
          clientInfo: %{name: "test_client", version: "1.0.0"}
        }
      })

      init_conn =
        conn(:post, "/", init_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      init_response = Router.call(init_conn, initialized_opts)
      assert init_response.status == 200

      # Send initialized notification to complete handshake
      initialized_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "notifications/initialized"
      })

      initialized_conn =
        conn(:post, "/", initialized_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      initialized_response = Router.call(initialized_conn, initialized_opts)
      assert initialized_response.status == 202

      # List tools
      list_body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "tools/list",
        id: "2",
        params: %{}
      })

      list_conn =
        conn(:post, "/", list_body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      list_response = Router.call(list_conn, initialized_opts)
      assert list_response.status == 200

      resp = Jason.decode!(list_response.resp_body)
      assert resp["jsonrpc"] == "2.0"

      # Verify tools are listed
      tools = resp["result"]["tools"]
      assert is_list(tools)
      assert length(tools) > 0, "Expected tools to be listed"

      # Verify list_artists is in the tools
      assert Enum.any?(tools, fn tool -> tool["name"] == "list_artists" end)
    end
  end
end
