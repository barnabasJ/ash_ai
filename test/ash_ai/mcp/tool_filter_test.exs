defmodule AshAi.Mcp.ToolFilterTest do
  use AshAi.RepoCase, async: false
  import Plug.{Conn, Test}

  alias AshAi.Mcp.Router

  @opts [tools: [:list_artists], otp_app: :ash_ai]

  describe "tool filter bug fix" do
    test "tools/call request works without filter error" do
      # First initialize a session
      init_conn =
        conn(
          :post,
          "/",
          %{
            method: "initialize",
            id: "1",
            params: %{
              client: %{
                name: "test_client",
                version: "1.0.0"
              }
            }
          }
        )

      init_response = Router.call(init_conn, @opts)
      session_id = List.first(get_resp_header(init_response, "mcp-session-id"))

      # Now make a tools/call request
      # This is where the bug happens - the filter tries to access tool.mcp
      call_conn =
        conn(
          :post,
          "/",
          %{
            method: "tools/call",
            id: "2",
            params: %{
              name: "list_artists",
              arguments: %{}
            }
          }
        )
        |> put_req_header("mcp-session-id", session_id)

      # This should work without errors
      # Before fix: Would fail because filter tries to access non-existent tool.mcp field
      call_response = Router.call(call_conn, @opts)

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
      # Initialize session
      init_conn =
        conn(
          :post,
          "/",
          %{
            method: "initialize",
            id: "1",
            params: %{
              client: %{name: "test_client", version: "1.0.0"}
            }
          }
        )

      init_response = Router.call(init_conn, @opts)
      session_id = List.first(get_resp_header(init_response, "mcp-session-id"))

      # List tools
      list_conn =
        conn(:post, "/", %{
          method: "tools/list",
          id: "2",
          params: %{}
        })
        |> put_req_header("mcp-session-id", session_id)

      list_response = Router.call(list_conn, @opts)
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
