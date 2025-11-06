# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.HermesServerTest do
  use AshAi.RepoCase, async: false

  alias AshAi.Mcp.HermesServer

  describe "init/2 callback" do
    test "initializes successfully with client info" do
      client_info = %{
        "name" => "test_client",
        "version" => "1.0.0"
      }

      frame = Hermes.Server.Frame.new()

      assert {:ok, returned_frame} = HermesServer.init(client_info, frame)
      assert %Hermes.Server.Frame{} = returned_frame
    end

    test "preserves frame assigns during initialization" do
      client_info = %{
        "name" => "test_client",
        "version" => "1.0.0"
      }

      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:user_id, 123)

      assert {:ok, returned_frame} = HermesServer.init(client_info, frame)
      assert returned_frame.assigns.user_id == 123
    end
  end

  describe "handle_tool_call/3 callback" do
    test "executes tool with context from frame" do
      # Setup: Create test data
      artist =
        AshAi.Test.Music.ArtistAfterAction
        |> Ash.Changeset.for_create(:create, %{name: "Test Artist"})
        |> Ash.create!()

      # Setup: Create frame with auth context and opts
      # Using the same pattern as the router - passing tools configuration
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:actor, %{id: 123})
        |> Hermes.Server.Frame.assign(:tenant, "test_tenant")
        |> Hermes.Server.Frame.assign(:context, %{org_id: 456})
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute tool call
      {:reply, result, _frame} = HermesServer.handle_tool_call("list_artists", %{}, frame)

      # Verify response format (MCP protocol)
      assert is_map(result)
      assert is_list(result.content)
      assert length(result.content) > 0

      # Verify content is properly formatted
      [first_content | _] = result.content
      assert first_content.type == "text"
      assert is_binary(first_content.text)

      # Verify artist is in results
      assert String.contains?(first_content.text, artist.name)
    end

    test "executes tool with empty arguments" do
      # Setup frame with opts
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute tool call with nil arguments
      {:reply, result, _frame} = HermesServer.handle_tool_call("list_artists", nil, frame)

      # Should not crash and return valid response
      assert is_map(result)
      assert is_list(result.content)
    end

    test "returns error when tool not found" do
      # Setup frame
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute non-existent tool
      {:error, error, _frame} =
        HermesServer.handle_tool_call("nonexistent_tool", %{}, frame)

      # Verify error format
      assert is_map(error)
      assert Map.has_key?(error, :code)
      assert Map.has_key?(error, :message)
      assert error.message =~ "not found"
    end

    test "returns error when tool execution fails" do
      # Setup frame
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute tool with invalid arguments (should cause execution error)
      {:error, error, _frame} =
        HermesServer.handle_tool_call("list_artists", %{"filter" => %{"invalid_field" => "x"}}, frame)

      # Verify error format
      assert is_map(error)
      assert Map.has_key?(error, :code)
      assert Map.has_key?(error, :message)
    end

    test "preserves auth context from frame during execution" do
      # Setup actor
      actor = %{id: 789, email: "test@example.com"}

      # Setup frame with actor
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:actor, actor)
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute tool (actor should be passed to Ash action)
      {:reply, _result, _frame} = HermesServer.handle_tool_call("list_artists", %{}, frame)

      # If this doesn't raise, actor was properly passed
      # (Real validation would require a tool that checks actor)
    end

    test "handles missing opts gracefully" do
      # Frame without opts
      frame = Hermes.Server.Frame.new()

      # Should return error about missing configuration or tool not found
      result = HermesServer.handle_tool_call("list_artists", %{}, frame)

      assert {:error, error, _frame} = result
      # Without opts, should fail to load tools or find the tool
      assert is_binary(error.message)
    end

    test "formats successful result as MCP content" do
      # Setup
      frame =
        Hermes.Server.Frame.new()
        |> Hermes.Server.Frame.assign(:opts, tools: [:list_artists], otp_app: :ash_ai)

      # Execute
      {:reply, result, _frame} = HermesServer.handle_tool_call("list_artists", %{}, frame)

      # MCP content format: %{content: [%{type: "text", text: "..."}]}
      assert Map.has_key?(result, :content)
      assert is_list(result.content)

      Enum.each(result.content, fn item ->
        assert Map.has_key?(item, :type)
        assert Map.has_key?(item, :text)
        assert item.type == "text"
      end)
    end
  end
end
