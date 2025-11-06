# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ToolBridge do
  @moduledoc """
  Bridges AshAi tool definitions to Hermes MCP component format.

  This module provides transformation functions to convert tools defined via
  the AshAi DSL into Hermes-compatible tool components. It preserves all
  tool metadata (names, descriptions, schemas) while adapting the format
  for use with Hermes.Server.

  ## Purpose

  The ToolBridge enables preserving the AshAi `tools do` DSL while using
  Hermes for MCP protocol handling internally. This provides a seamless
  migration path without breaking changes for users.

  ## Architecture

  Tools flow through these stages:
  1. Extract from domains via `AshAi.Info.tools/1`
  2. Filter according to options (tool list or filter function)
  3. Transform each tool definition to Hermes format
  4. Convert LangChain.Function schemas to JSON Schema

  ## Usage

      # Extract and transform tools for Hermes registration
      domains = [MyApp.Blog, MyApp.Shop]
      tool_filter = [:list_posts, :create_post]

      hermes_tools = ToolBridge.to_hermes_tools(domains, tool_filter)
  """

  @doc """
  Transforms AshAi domain tools to Hermes component format.

  Extracts tools from the provided domains using `AshAi.Info.tools/1`,
  applies filtering based on the tool_filter parameter, and transforms
  each tool to Hermes-compatible format.

  ## Parameters

    * `domains` - List of Ash domains providing tools
    * `tool_filter` - List of tool names to include, or nil for all tools

  ## Returns

  List of Hermes tool component structs ready for registration.

  ## Examples

      iex> ToolBridge.to_hermes_tools([MyApp.Blog], [:list_posts])
      [%{name: "list_posts", description: "...", input_schema: %{...}}]

      iex> ToolBridge.to_hermes_tools([MyApp.Blog], nil)
      # Returns all tools from MyApp.Blog domain
  """
  def to_hermes_tools(domains, tool_filter) do
    domains
    |> Enum.flat_map(fn domain ->
      domain
      |> AshAi.Info.tools()
      |> Enum.map(fn tool ->
        # Enrich tool with domain and action info like exposed_tools does
        %{
          tool
          | domain: domain,
            action: Ash.Resource.Info.action(tool.resource, tool.action)
        }
      end)
    end)
    |> filter_tools(tool_filter)
    |> Enum.map(&transform_tool_definition/1)
  end

  @doc """
  Filters tools according to the provided filter specification.

  ## Parameters

    * `tools` - List of tool definitions from AshAi.Info.tools/1
    * `filter` - List of tool names to include, or nil for all tools

  ## Returns

  Filtered list of tools.
  """
  def filter_tools(tools, nil), do: tools

  def filter_tools(tools, filter) when is_list(filter) do
    Enum.filter(tools, fn tool -> tool.name in filter end)
  end

  @doc """
  Transforms a single AshAi tool definition to Hermes component format.

  Converts the tool metadata and builds the parameter schema directly
  from the action definition.

  ## Parameters

    * `tool_def` - Tool definition from AshAi.Info.tools/1 (enriched with domain and action)

  ## Returns

  Map with Hermes tool component fields:
    * `:name` - Tool identifier
    * `:description` - Human-readable description
    * `:input_schema` - JSON Schema for tool parameters
  """
  def transform_tool_definition(tool_def) do
    name = to_string(tool_def.name)
    action = tool_def.action
    resource = tool_def.resource

    description =
      String.trim(
        tool_def.description || action.description ||
          "Call the #{action.name} action on the #{inspect(resource)} resource"
      )

    parameter_schema = build_parameter_schema(tool_def.domain, resource, action, tool_def.action_parameters)

    %{
      name: name,
      description: description,
      input_schema: parameter_schema
    }
  end

  @doc """
  Builds the parameter schema for a tool action.

  This replicates the logic from AshAi.parameter_schema/4 to build
  JSON Schema for the tool's parameters.

  ## Parameters

    * `domain` - The Ash domain
    * `resource` - The Ash resource
    * `action` - The action struct
    * `action_parameters` - Additional action parameters

  ## Returns

  JSON Schema map with type, properties, and required fields.
  """
  def build_parameter_schema(_domain, resource, action, action_parameters) do
    attributes =
      if action.type in [:action, :read] do
        %{}
      else
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.filter(&(&1.name in action.accept && &1.writable?))
        |> Map.new(fn attribute ->
          value =
            AshAi.OpenApi.resource_write_attribute_type(
              attribute,
              resource,
              action.type
            )

          {attribute.name, value}
        end)
      end

    properties =
      action.arguments
      |> Enum.filter(& &1.public?)
      |> Enum.reduce(attributes, fn argument, attributes ->
        value =
          AshAi.OpenApi.resource_write_attribute_type(argument, resource, :create)

        Map.put(
          attributes,
          argument.name,
          value
        )
      end)

    props_with_input =
      if Enum.empty?(properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: properties,
            required: AshAi.OpenApi.required_write_attributes(resource, action.arguments, action)
          }
        }
      end

    %{
      type: :object,
      properties:
        add_action_specific_properties(props_with_input, resource, action, action_parameters),
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> Jason.encode!()
    |> Jason.decode!()
  end

  # Helper to add action-specific properties
  defp add_action_specific_properties(props, resource, action, action_parameters) do
    case action.type do
      :read ->
        read_properties(props, resource, action)

      _ ->
        other_properties(props, resource, action, action_parameters)
    end
  end

  defp read_properties(props, _resource, action) do
    props
    |> Map.put(:filter, %{
      type: :object,
      description: "Filter the results"
    })
    |> Map.put(:sort, %{
      type: :array,
      description: "Sort the results",
      items: %{
        type: :object,
        properties: %{
          field: %{type: :string},
          direction: %{type: :string, enum: ["asc", "desc"]}
        }
      }
    })
    |> Map.put(:limit, %{type: :integer, description: "Limit the number of results"})
    |> Map.put(:offset, %{type: :integer, description: "Skip a number of results"})
    |> then(fn props ->
      if action.pagination do
        Map.put(props, :result_type, %{
          type: :string,
          enum: ["run_query", "count", "exists"],
          description: "The type of result to return"
        })
      else
        props
      end
    end)
  end

  defp other_properties(props, _resource, _action, action_parameters) do
    if action_parameters do
      Map.put(props, :action_parameters, %{
        type: :object,
        description: "Parameters for the action"
      })
    else
      props
    end
  end

  @doc """
  Converts LangChain.Function schema to JSON Schema format.

  Transforms the function's parameters_schema (OpenAPI format) into
  JSON Schema format expected by Hermes and MCP protocol.

  ## Parameters

    * `function` - LangChain.Function struct with parameters_schema

  ## Returns

  JSON Schema map with type, properties, and required fields.

  ## Examples

      iex> function = %LangChain.Function{parameters_schema: %{...}}
      iex> ToolBridge.map_function_schema(function)
      %{"type" => "object", "properties" => %{...}, "required" => [...]}
  """
  def map_function_schema(%LangChain.Function{} = function) do
    schema = function.parameters_schema || %{}

    # Convert OpenAPI schema to JSON Schema
    # The parameters_schema is already in a compatible format from OpenAPI Spex
    %{
      "type" => schema["type"] || "object",
      "properties" => schema["properties"] || %{},
      "required" => schema["required"] || []
    }
  end
end
