# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ServerTest do
  @moduledoc """
  Tests for the Hermes MCP-based server implementation.

  These tests verify that the MCP server properly:
  - Initializes with protocol handshake
  - Lists available tools from AshAi configuration
  - Executes tools and returns properly formatted results
  - Handles errors appropriately
  """

  use AshAi.RepoCase, async: false
  import Plug.{Conn, Test}

  alias AshAi.Mcp.Router
  alias AshAi.Test.Music

  @opts [tools: [:list_artists], otp_app: :ash_ai]

  setup do
    # Clean up any existing server instances before each test
    server_name = server_name_for_opts(@opts)

    case Process.whereis(server_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5000)
    end

    :ok
  end

  describe "MCP RPC Protocol with Hermes" do
    test "initialization creates a session" do
      conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            id: "1",
            params: %{
              protocolVersion: "2025-03-26",
              clientInfo: %{
                name: "test_client",
                version: "1.0.0"
              },
              capabilities: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      response =
        conn
        |> Router.init(@opts)
        |> then(&Router.call(conn, &1))

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["application/json"]

      resp = Jason.decode!(response.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "1"
      assert resp["result"]["serverInfo"]["name"] == "AshAi MCP Server"
      assert resp["result"]["serverInfo"]["version"] == "0.3.0"
      assert resp["result"]["protocolVersion"] != nil
    end

    test "lists available tools" do
      # First initialize
      init_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            id: "1",
            params: %{
              protocolVersion: "2025-03-26",
              clientInfo: %{name: "test_client", version: "1.0.0"},
              capabilities: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      opts = Router.init(@opts)
      _init_response = Router.call(init_conn, opts)

      # Now list tools
      list_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "tools/list",
            id: "2"
          })
        )
        |> put_req_header("content-type", "application/json")

      response = Router.call(list_conn, opts)
      assert response.status == 200

      resp = Jason.decode!(response.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "2"
      assert is_list(resp["result"]["tools"])

      # Check that list_artists tool is present
      tools = resp["result"]["tools"]
      assert Enum.any?(tools, fn tool -> tool["name"] == "list_artists" end)
    end

    test "handles tool execution requests" do
      # First initialize
      init_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            id: "1",
            params: %{
              protocolVersion: "2025-03-26",
              clientInfo: %{name: "test_client", version: "1.0.0"},
              capabilities: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      opts = Router.init(@opts)
      _init_response = Router.call(init_conn, opts)

      # Create an artist to list
      Music.create_artist_after_action!(%{
        name: "Test Artist",
        bio: "A test artist for MCP tools testing"
      })

      # Now try to execute the list_artists tool
      tool_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "tools/call",
            id: "2",
            params: %{
              name: "list_artists",
              arguments: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      response = Router.call(tool_conn, opts)
      assert response.status == 200

      resp = Jason.decode!(response.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "2"

      # Check the result structure
      assert resp["result"] != nil
      assert is_list(resp["result"]["content"])
      assert length(resp["result"]["content"]) > 0

      # Get the text content
      [content_item | _] = resp["result"]["content"]
      assert content_item["type"] == "text"
      text = content_item["text"]

      # Check that our test artist is in the results
      artists = Jason.decode!(text)
      assert is_list(artists)
      assert Enum.any?(artists, fn a -> a["name"] == "Test Artist" end)
    end

    test "handles tool not found error" do
      # First initialize
      init_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            id: "1",
            params: %{
              protocolVersion: "2025-03-26",
              clientInfo: %{name: "test_client", version: "1.0.0"},
              capabilities: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      opts = Router.init(@opts)
      _init_response = Router.call(init_conn, opts)

      # Try to call a non-existent tool
      tool_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "tools/call",
            id: "2",
            params: %{
              name: "nonexistent_tool",
              arguments: %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")

      response = Router.call(tool_conn, opts)
      assert response.status == 200

      resp = Jason.decode!(response.resp_body)
      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == "2"
      assert resp["error"] != nil
      assert resp["error"]["code"] == -32602
    end
  end

  # Helper function to generate server name (matches router implementation)
  defp server_name_for_opts(opts) do
    otp_app = opts[:otp_app] || :ash_ai
    tools = opts[:tools] || []

    tools_hash =
      :erlang.phash2({otp_app, tools})
      |> Integer.to_string()

    Module.concat([AshAi.Mcp.Server, "Instance#{tools_hash}"])
  end
end
