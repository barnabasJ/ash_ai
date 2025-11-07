defmodule ReqIsLove.Demo do
  @moduledoc """
  Demo Ash domain showcasing Hermes MCP integration.

  This domain exposes Task and Note resources via MCP protocol,
  demonstrating how to build MCP-enabled tools with Ash Framework.
  """

  use Ash.Domain,
    otp_app: :req_is_love,
    extensions: [AshAi]

  resources do
    resource(ReqIsLove.Demo.Task)
    resource(ReqIsLove.Demo.Note)
  end

  tools do
    tool :list_tasks, ReqIsLove.Demo.Task, :read do
      description "List all tasks in the system"
    end

    tool :create_task, ReqIsLove.Demo.Task, :create do
      description "Create a new task with title and optional description"
    end

    tool :complete_task, ReqIsLove.Demo.Task, :complete do
      description "Mark a task as completed by its ID"
    end

    tool :search_notes, ReqIsLove.Demo.Note, :search do
      description "Search notes by query string in title or body"
    end

    tool :create_note, ReqIsLove.Demo.Note, :create do
      description "Create a new note with title and body content"
    end
  end
end
