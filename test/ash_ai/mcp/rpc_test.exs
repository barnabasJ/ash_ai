# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ServerTest do
  use AshAi.RepoCase, async: false
  import Plug.{Conn, Test}

  alias AshAi.Mcp.Plug, as: McpPlug
  alias AshAi.Test.Music

  @opts McpPlug.init(domains: [AshAi.Test.Music], tools: [:list_artists], otp_app: :ash_ai)

  describe "MCP RPC Protocol with Hermes" do
    @tag :skip
    test "initialization creates a session via SSE endpoint" do
      # SSE is a persistent streaming connection that never completes
      # This test would timeout - need different testing approach for SSE
      # TODO: Mock or spawn async process to test SSE properly
      # First connect to SSE endpoint to get session
      conn = conn(:get, "/")
              |> put_req_header("accept", "text/event-stream")

      response = McpPlug.call(conn, @opts)
      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["text/event-stream"]

      # SSE endpoint provides connection, real initialization happens via POST
    end

    test "sends initialize message to get server info" do
      body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "initialize",
        id: "1",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{},
          clientInfo: %{
            name: "test_client",
            version: "1.0.0"
          }
        }
      })

      conn =
        conn(
          :post,
          "/",
          body
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")

      response = McpPlug.call(conn, @opts)

      # Debug: Print response if not 200
      if response.status != 200 do
        IO.puts("Response status: #{response.status}")
        IO.puts("Response body: #{response.resp_body}")
      end

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]

      resp = Jason.decode!(response.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "1"
      assert resp["result"]["serverInfo"]["name"] =~ "AshAi"
    end

    test "handles tool execution requests" do
      # Create an artist to list
      Music.create_artist_after_action!(%{
        name: "Test Artist",
        bio: "A test artist for MCP tools testing"
      })

      # Use a consistent session ID across requests
      session_id = "session_test_#{:rand.uniform(1000000)}"

      # First initialize the server
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

      init_response = McpPlug.call(init_conn, @opts)
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

      initialized_response = McpPlug.call(initialized_conn, @opts)
      # Notifications return 202 Accepted
      assert initialized_response.status == 202

      # Now execute the list_artists tool via Hermes protocol (using same session)
      body = Jason.encode!(%{
        jsonrpc: "2.0",
        method: "tools/call",
        id: "2",
        params: %{
          name: "list_artists",
          arguments: %{}
        }
      })

      conn =
        conn(
          :post,
          "/",
          body
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("mcp-session-id", session_id)

      response = McpPlug.call(conn, @opts)
      assert response.status == 200

      resp = Jason.decode!(response.resp_body)

      # Debug: print full response if there's an error
      if Map.has_key?(resp, "error") do
        IO.puts("Error response: #{inspect(resp, pretty: true)}")
      end

      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "2"
      assert resp["result"] != nil
      assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = resp

      # Check that our test artist is in the results
      artists = Jason.decode!(text)
      assert Enum.any?(artists, fn a -> a["name"] == "Test Artist" end)
    end
  end
end
