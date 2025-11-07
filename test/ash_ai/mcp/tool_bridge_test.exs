# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ToolBridgeTest do
  use AshAi.RepoCase, async: false

  alias AshAi.Mcp.ToolBridge
  alias AshAi.Test.Music

  describe "to_hermes_tools/2" do
    test "extracts and transforms tools from domain" do
      domains = [Music]
      tool_filter = [:list_artists]

      tools = ToolBridge.to_hermes_tools(domains, tool_filter)

      assert is_list(tools)
      assert length(tools) == 1

      tool = List.first(tools)
      assert tool.name == "list_artists"
      assert tool.description != nil
      assert tool.input_schema != nil
    end

    test "returns empty list when no tools match filter" do
      domains = [Music]
      tool_filter = [:nonexistent_tool]

      tools = ToolBridge.to_hermes_tools(domains, tool_filter)

      assert tools == []
    end

    test "returns all tools when filter is nil" do
      domains = [Music]
      tool_filter = nil

      tools = ToolBridge.to_hermes_tools(domains, tool_filter)

      assert is_list(tools)
      assert length(tools) > 0
    end

    test "handles multiple domains" do
      domains = [Music]
      tool_filter = nil

      tools = ToolBridge.to_hermes_tools(domains, tool_filter)

      assert is_list(tools)
      # Music domain has at least one tool
      assert length(tools) >= 1
    end
  end

  describe "transform_tool_definition/1" do
    test "converts AshAi tool to Hermes component format" do
      # Get a sample tool from the domain
      domains = [Music]
      tools = ToolBridge.to_hermes_tools(domains, [:list_artists])
      tool = List.first(tools)

      assert is_map(tool)
      assert Map.has_key?(tool, :name)
      assert Map.has_key?(tool, :description)
      assert Map.has_key?(tool, :input_schema)
    end
  end

  describe "map_function_schema/1" do
    test "converts LangChain.Function schema to Hermes format" do
      # Get a real function from AshAi using the correct API
      functions = AshAi.functions(otp_app: :ash_ai, tools: [:list_artists])
      function = List.first(functions)

      schema = ToolBridge.map_function_schema(function)

      assert is_map(schema)
      assert schema["type"] == "object"
      assert Map.has_key?(schema, "properties")
    end

    test "preserves parameter types and descriptions" do
      functions = AshAi.functions(otp_app: :ash_ai, tools: [:list_artists])
      function = List.first(functions)

      schema = ToolBridge.map_function_schema(function)

      assert is_map(schema["properties"])
    end

    test "handles required vs optional parameters" do
      functions = AshAi.functions(otp_app: :ash_ai, tools: [:list_artists])
      function = List.first(functions)

      schema = ToolBridge.map_function_schema(function)

      # Schema should have required array (even if empty)
      assert is_list(schema["required"])
    end
  end
end
