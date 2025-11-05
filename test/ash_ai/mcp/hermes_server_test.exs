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
    test "returns placeholder response for now" do
      frame = Hermes.Server.Frame.new()

      assert {:reply, result, _frame} = HermesServer.handle_tool_call("list_artists", %{}, frame)
      assert result.content == [%{type: "text", text: "Not yet implemented"}]
    end
  end
end
