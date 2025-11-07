defmodule ReqIsLoveWeb.MCP.DemoSchemaResource do
  @moduledoc """
  MCP Resource that provides schema information for the Demo domain.

  This resource exposes the structure of the Demo domain including:
  - Available resources (Task, Note)
  - Attributes and their types
  - Available actions

  ## Usage

  Access this resource via URI: `demo://schema`
  """

  use Hermes.Server.Component, type: :resource

  @doc """
  Returns the resource definition for MCP protocol.

  This includes the URI, name, description, and MIME type.
  """
  def definition do
    %{
      uri: "demo://schema",
      name: "demo_schema",
      title: "Demo Schema",
      description: "Schema information for the Demo domain including Task and Note resources",
      mime_type: "application/json"
    }
  end

  @doc """
  Returns the resource content when read.

  Builds a JSON representation of the Demo domain schema including
  all resources, their attributes, and available actions.
  """
  def read(_uri, _frame) do
    schema = build_schema()
    {:ok, Jason.encode!(schema, pretty: true)}
  end

  # Private helper to build the schema
  defp build_schema do
    %{
      domain: "ReqIsLove.Demo",
      resources: [
        build_resource_schema(ReqIsLove.Demo.Task),
        build_resource_schema(ReqIsLove.Demo.Note)
      ]
    }
  end

  defp build_resource_schema(resource) do
    %{
      name: inspect(resource),
      short_name: resource |> Module.split() |> List.last(),
      attributes: build_attributes(resource),
      actions: build_actions(resource)
    }
  end

  defp build_attributes(resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.map(fn attr ->
      %{
        name: attr.name,
        type: inspect(attr.type),
        allow_nil?: attr.allow_nil?,
        public?: attr.public?,
        primary_key?: attr.primary_key?
      }
    end)
  end

  defp build_actions(resource) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.map(fn action ->
      %{
        name: action.name,
        type: action.type,
        description: action.description,
        accept:
          if action.type in [:create, :update] do
            Enum.map(action.accept, &to_string/1)
          else
            []
          end,
        arguments:
          Enum.map(action.arguments, fn arg ->
            %{
              name: arg.name,
              type: inspect(arg.type),
              allow_nil?: arg.allow_nil?,
              public?: arg.public?
            }
          end)
      }
    end)
  end
end
