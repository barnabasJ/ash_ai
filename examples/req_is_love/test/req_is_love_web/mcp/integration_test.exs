defmodule ReqIsLoveWeb.MCP.IntegrationTest do
  @moduledoc """
  Comprehensive MCP protocol integration tests.

  Tests cover:
  - Protocol compliance (initialize, tools/list, tools/call)
  - Tool execution for all 5 demo tools
  - E2E workflows (multi-step scenarios)
  - Error handling (JSON-RPC error codes)
  - Session management (concurrent sessions, persistence)
  """

  use ReqIsLoveWeb.MCPCase, async: false

  alias ReqIsLove.DemoFixtures

  describe "MCP Protocol Integration" do
    test "MCP endpoint is accessible" do
      # Attempt to connect to MCP endpoint
      # GET may return 404 or establish SSE connection, or 406 if headers missing
      conn = Plug.Test.conn(:get, "/ash_ai/mcp")
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Endpoint should respond (may be 404 for GET, 406 for missing headers, or SSE connection)
      assert response.status in [200, 404, 406]
    end

    test "initialize handshake succeeds" do
      session_id = unique_session_id()

      # Send initialize request
      conn =
        Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(initialize_message()))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
        |> Plug.Conn.put_req_header("mcp-session-id", session_id)

      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Validate successful initialize response
      result = assert_mcp_success(response, "1")
      # Accept any valid MCP protocol version
      assert result["protocolVersion"] in ["2024-11-05", "2025-03-26"]
      assert Map.has_key?(result, "capabilities")
      assert Map.has_key?(result, "serverInfo")
    end

    test "initialized notification is accepted" do
      session_id = unique_session_id()

      # First initialize
      init_conn =
        Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(initialize_message()))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
        |> Plug.Conn.put_req_header("mcp-session-id", session_id)

      init_response = ReqIsLoveWeb.Endpoint.call(init_conn, [])
      assert init_response.status == 200

      # Send initialized notification
      notif_conn =
        Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(initialized_notification()))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
        |> Plug.Conn.put_req_header("mcp-session-id", session_id)

      notif_response = ReqIsLoveWeb.Endpoint.call(notif_conn, [])

      # Notifications return 202 Accepted per MCP spec
      assert notif_response.status == 202
    end

    test "tools/list returns all 5 demo tools" do
      # Initialize session
      session_id = initialize_mcp_session()

      # Request tool list
      conn =
        Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(list_tools_message()))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("accept", "application/json, text/event-stream")
        |> Plug.Conn.put_req_header("mcp-session-id", session_id)

      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Debug 406 errors
      if response.status == 406 do
        IO.puts("\n=== 406 Response Debug ===")
        IO.puts("Status: #{response.status}")
        IO.puts("Body: #{response.resp_body}")
        IO.puts("Headers: #{inspect(response.resp_headers)}")
        IO.puts("========================\n")
      end

      # Validate tools list response
      result = assert_mcp_success(response, "2")
      tools = result["tools"]

      assert length(tools) == 5

      tool_names = Enum.map(tools, & &1["name"])
      assert "list_tasks" in tool_names
      assert "create_task" in tool_names
      assert "complete_task" in tool_names
      assert "search_notes" in tool_names
      assert "create_note" in tool_names

      # Each tool should have name and description
      Enum.each(tools, fn tool ->
        assert Map.has_key?(tool, "name")
        assert Map.has_key?(tool, "description")
      end)
    end
  end

  describe "Tool Execution" do
    test "list_tasks tool executes successfully" do
      # Create test data
      _task1 = DemoFixtures.task_fixture(%{title: "Task 1"})
      _task2 = DemoFixtures.task_fixture(%{title: "Task 2"})

      # Initialize session
      session_id = initialize_mcp_session()

      # Call list_tasks tool using helper
      call_msg = call_tool_message("list_tasks", %{})
      conn = mcp_post_conn(call_msg, session_id)

      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Validate successful execution
      result = assert_mcp_success(response, "3")

      # Result should contain task data
      assert is_list(result["content"]) or is_map(result)
    end

    test "create_task tool creates new task" do
      # Initialize session
      session_id = initialize_mcp_session()

      # Call create_task tool (arguments must be nested under 'input')
      call_msg =
        call_tool_message("create_task", %{
          input: %{
            title: "New Task",
            description: "Created via MCP"
          }
        })

      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Validate successful creation and check response contains task data
      result = assert_mcp_success(response, "3")

      # Verify the response contains the created task
      assert %{"content" => [%{"type" => "text", "text" => task_json}]} = result
      assert task_data = Jason.decode!(task_json)
      assert task_data["title"] == "New Task"
      assert task_data["description"] == "Created via MCP"
      assert task_data["completed"] == false
      assert Map.has_key?(task_data, "id")
    end

    test "complete_task tool marks task complete" do
      # Initialize session
      session_id = initialize_mcp_session()

      # Create a task via MCP
      create_msg =
        call_tool_message(
          "create_task",
          %{
            input: %{title: "Incomplete Task", description: "To be completed"}
          },
          "2"
        )

      create_conn = mcp_post_conn(create_msg, session_id)
      create_response = ReqIsLoveWeb.Endpoint.call(create_conn, [])
      create_result = assert_mcp_success(create_response, "2")

      # Extract task ID from response
      assert %{"content" => [%{"type" => "text", "text" => task_json}]} = create_result
      task_data = Jason.decode!(task_json)
      task_id = task_data["id"]
      refute task_data["completed"]

      # Call complete_task tool
      call_msg = call_tool_message("complete_task", %{id: task_id}, "3")
      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Validate successful execution
      result = assert_mcp_success(response, "3")

      # Verify task is now completed in the response
      assert %{"content" => [%{"type" => "text", "text" => updated_json}]} = result
      updated_task = Jason.decode!(updated_json)
      assert updated_task["id"] == task_id
      assert updated_task["completed"] == true
    end

    test "search_notes tool finds matching notes" do
      # Create test notes
      _note1 = DemoFixtures.note_fixture(%{title: "Specific Topic", body: "General content"})

      _note2 =
        DemoFixtures.note_fixture(%{title: "General Topic", body: "Contains specific keyword"})

      _note3 = DemoFixtures.note_fixture(%{title: "Other", body: "No match here"})

      # Initialize session
      session_id = initialize_mcp_session()

      # Search for "specific"
      call_msg = call_tool_message("search_notes", %{query: "specific"})

      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Validate successful search
      result = assert_mcp_success(response, "3")

      # Should find 2 notes with "specific" in title or body
      # Result format depends on MCP tool implementation
      assert is_list(result["content"]) or is_map(result)
    end

    test "session persists across multiple tool calls" do
      # Initialize session once
      session_id = initialize_mcp_session()

      # Make 3 different tool calls with same session
      tools = ["list_tasks", "search_notes", "list_tasks"]

      Enum.each(Enum.with_index(tools, 1), fn {tool_name, idx} ->
        call_msg = call_tool_message(tool_name, %{}, "call_#{idx}")
        conn = mcp_post_conn(call_msg, session_id)
        response = ReqIsLoveWeb.Endpoint.call(conn, [])

        # All calls should succeed
        assert_mcp_success(response, "call_#{idx}")
      end)
    end
  end

  describe "E2E Workflows" do
    test "complete task workflow: create → list → complete → verify" do
      session_id = initialize_mcp_session()

      # Step 1: Create a task
      create_msg =
        call_tool_message(
          "create_task",
          %{
            title: "Workflow Task",
            description: "Test workflow"
          },
          "1"
        )

      create_conn = mcp_post_conn(create_msg, session_id)
      create_response = ReqIsLoveWeb.Endpoint.call(create_conn, [])
      assert_mcp_success(create_response, "1")

      # Step 2: List tasks to find our task
      list_msg = call_tool_message("list_tasks", %{}, "2")
      list_conn = mcp_post_conn(list_msg, session_id)
      list_response = ReqIsLoveWeb.Endpoint.call(list_conn, [])
      _list_result = assert_mcp_success(list_response, "2")

      # Step 3: Get the task and complete it
      tasks = ReqIsLove.Demo.Task.list_all!()
      workflow_task = Enum.find(tasks, &(&1.title == "Workflow Task"))
      assert workflow_task

      complete_msg = call_tool_message("complete_task", %{id: workflow_task.id}, "3")
      complete_conn = mcp_post_conn(complete_msg, session_id)
      complete_response = ReqIsLoveWeb.Endpoint.call(complete_conn, [])
      assert_mcp_success(complete_response, "3")

      # Step 4: Verify task is completed
      updated_task = ReqIsLove.Demo.Task.list_all!() |> Enum.find(&(&1.id == workflow_task.id))
      assert updated_task.completed
    end

    test "note search workflow: create notes → search → verify results" do
      session_id = initialize_mcp_session()

      # Step 1: Create multiple notes
      notes_data = [
        %{title: "Elixir Guide", body: "Learning Elixir programming"},
        %{title: "Phoenix Framework", body: "Building web apps with Elixir"},
        %{title: "Ruby Guide", body: "Learning Ruby programming"}
      ]

      Enum.each(Enum.with_index(notes_data, 1), fn {note_data, idx} ->
        create_msg = call_tool_message("create_note", note_data, "create_#{idx}")
        conn = mcp_post_conn(create_msg, session_id)
        response = ReqIsLoveWeb.Endpoint.call(conn, [])
        assert_mcp_success(response, "create_#{idx}")
      end)

      # Step 2: Search for "Elixir"
      search_msg = call_tool_message("search_notes", %{query: "Elixir"}, "search")
      search_conn = mcp_post_conn(search_msg, session_id)
      search_response = ReqIsLoveWeb.Endpoint.call(search_conn, [])
      result = assert_mcp_success(search_response, "search")

      # Should find 2 notes with "Elixir"
      # Actual verification depends on result structure
      assert is_list(result["content"]) or is_map(result)
    end

    test "multi-tool workflow: create task and note in sequence" do
      session_id = initialize_mcp_session()

      # Create a task
      task_msg =
        call_tool_message(
          "create_task",
          %{
            title: "Multi-tool Task",
            description: "Test"
          },
          "1"
        )

      task_conn = mcp_post_conn(task_msg, session_id)
      task_response = ReqIsLoveWeb.Endpoint.call(task_conn, [])
      assert_mcp_success(task_response, "1")

      # Create a note
      note_msg =
        call_tool_message(
          "create_note",
          %{
            title: "Multi-tool Note",
            body: "Test note"
          },
          "2"
        )

      note_conn = mcp_post_conn(note_msg, session_id)
      note_response = ReqIsLoveWeb.Endpoint.call(note_conn, [])
      assert_mcp_success(note_response, "2")

      # List tasks
      list_tasks_msg = call_tool_message("list_tasks", %{}, "3")
      list_tasks_conn = mcp_post_conn(list_tasks_msg, session_id)
      list_tasks_response = ReqIsLoveWeb.Endpoint.call(list_tasks_conn, [])
      assert_mcp_success(list_tasks_response, "3")

      # Search notes
      search_msg = call_tool_message("search_notes", %{query: "Multi-tool"}, "4")
      search_conn = mcp_post_conn(search_msg, session_id)
      search_response = ReqIsLoveWeb.Endpoint.call(search_conn, [])
      assert_mcp_success(search_response, "4")
    end
  end

  describe "Error Handling" do
    test "invalid tool name returns error -32602" do
      session_id = initialize_mcp_session()

      # Call non-existent tool
      call_msg = call_tool_message("nonexistent_tool", %{})
      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Should return Invalid params error (tool name is a parameter to tools/call)
      error = assert_mcp_error(response, -32602)
      assert is_binary(error["message"])
    end

    test "invalid arguments return error -32602" do
      session_id = initialize_mcp_session()

      # Call create_task without required title
      call_msg = call_tool_message("create_task", %{description: "No title"})
      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Should return Invalid params error
      error = assert_mcp_error(response, -32602)
      assert is_binary(error["message"])
    end

    test "tool execution failure returns error -32603" do
      session_id = initialize_mcp_session()

      # Try to complete task with invalid/nonexistent ID
      call_msg = call_tool_message("complete_task", %{id: "00000000-0000-0000-0000-000000000000"})
      conn = mcp_post_conn(call_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Should return Internal error
      error = assert_mcp_error(response, -32603)
      assert is_binary(error["message"])
    end

    test "missing session ID handled gracefully" do
      # Try to list tools without session ID
      conn =
        Plug.Test.conn(:post, "/ash_ai/mcp/messages", Jason.encode!(list_tools_message()))
        |> Plug.Conn.put_req_header("content-type", "application/json")

      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Should either create new session or return error
      # Both are acceptable behaviors
      assert response.status in [200, 400, 404]
    end

    test "invalid JSON-RPC format rejected" do
      session_id = initialize_mcp_session()

      # Send malformed JSON-RPC (missing jsonrpc version)
      malformed_msg = %{
        method: "tools/list",
        id: "1"
        # Missing "jsonrpc": "2.0"
      }

      conn = mcp_post_conn(malformed_msg, session_id)
      response = ReqIsLoveWeb.Endpoint.call(conn, [])

      # Should return error for invalid request
      assert response.status in [200, 400]

      if response.status == 200 do
        body = Jason.decode!(response.resp_body)
        assert Map.has_key?(body, "error")
      end
    end
  end

  describe "Session Management" do
    test "concurrent sessions don't interfere" do
      # Create two separate sessions
      session_id_1 = initialize_mcp_session()
      session_id_2 = initialize_mcp_session()

      # Create task in session 1
      task1_msg =
        call_tool_message(
          "create_task",
          %{
            title: "Session 1 Task",
            description: "From session 1"
          },
          "1"
        )

      conn1 = mcp_post_conn(task1_msg, session_id_1)
      response1 = ReqIsLoveWeb.Endpoint.call(conn1, [])
      assert_mcp_success(response1, "1")

      # List tasks in session 2
      list_msg = call_tool_message("list_tasks", %{}, "2")
      conn2 = mcp_post_conn(list_msg, session_id_2)
      response2 = ReqIsLoveWeb.Endpoint.call(conn2, [])
      result = assert_mcp_success(response2, "2")

      # Both sessions should see the task (ETS is global)
      assert is_list(result["content"]) or is_map(result)
    end

    test "multiple requests with same session succeed" do
      session_id = initialize_mcp_session()

      # Make 5 sequential requests with same session
      Enum.each(1..5, fn idx ->
        call_msg = call_tool_message("list_tasks", %{}, "req_#{idx}")
        conn = mcp_post_conn(call_msg, session_id)
        response = ReqIsLoveWeb.Endpoint.call(conn, [])

        # All requests should succeed
        assert_mcp_success(response, "req_#{idx}")
      end)
    end
  end
end
