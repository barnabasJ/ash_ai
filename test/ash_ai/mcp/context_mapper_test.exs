# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Mcp.ContextMapperTest do
  @moduledoc """
  Tests for AshAi.Mcp.ContextMapper module.

  This module tests the transformation between Plug conn context
  and Hermes.Server.Frame context for authentication and authorization.
  """
  use ExUnit.Case, async: false

  alias AshAi.Mcp.ContextMapper
  alias Hermes.Server.Frame

  describe "to_frame/2" do
    test "extracts actor from conn and assigns to frame" do
      # Setup mock conn with actor using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_actor(%{id: 123, email: "test@example.com"})

      # Create initial frame
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert
      assert result_frame.assigns.actor == %{id: 123, email: "test@example.com"}
    end

    test "extracts tenant from conn and assigns to frame" do
      # Setup mock conn with tenant using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_tenant("tenant_123")

      # Create initial frame
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert
      assert result_frame.assigns.tenant == "tenant_123"
    end

    test "extracts context from conn and assigns to frame" do
      # Setup mock conn with context using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_context(%{org_id: 456, permissions: [:read, :write]})

      # Create initial frame
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert
      assert result_frame.assigns.context == %{org_id: 456, permissions: [:read, :write]}
    end

    test "handles missing actor gracefully" do
      # Setup conn without actor
      conn = Plug.Test.conn(:get, "/")
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert - should have nil or not crash
      assert Map.has_key?(result_frame.assigns, :actor)
      assert result_frame.assigns.actor == nil
    end

    test "handles missing tenant gracefully" do
      # Setup conn without tenant
      conn = Plug.Test.conn(:get, "/")
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert
      assert Map.has_key?(result_frame.assigns, :tenant)
      assert result_frame.assigns.tenant == nil
    end

    test "handles missing context with default empty map" do
      # Setup conn without context
      conn = Plug.Test.conn(:get, "/")
      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert - should default to empty map like server.ex:27
      assert result_frame.assigns.context == %{}
    end

    test "extracts all three contexts together" do
      # Setup conn with all contexts using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_actor(%{id: 123, email: "test@example.com"})
        |> Ash.PlugHelpers.set_tenant("tenant_123")
        |> Ash.PlugHelpers.set_context(%{org_id: 456})

      frame = %Frame{assigns: %{}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert all are present
      assert result_frame.assigns.actor == %{id: 123, email: "test@example.com"}
      assert result_frame.assigns.tenant == "tenant_123"
      assert result_frame.assigns.context == %{org_id: 456}
    end

    test "preserves existing frame assigns" do
      # Setup conn using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_actor(%{id: 123})

      # Frame with existing assigns
      frame = %Frame{assigns: %{existing_key: "existing_value"}}

      # Act
      result_frame = ContextMapper.to_frame(conn, frame)

      # Assert both old and new assigns are present
      assert result_frame.assigns.existing_key == "existing_value"
      assert result_frame.assigns.actor == %{id: 123}
    end
  end

  describe "from_frame/1" do
    test "extracts actor from frame" do
      # Setup frame with actor
      frame = %Frame{
        assigns: %{
          actor: %{id: 123, email: "test@example.com"}
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert
      assert result[:actor] == %{id: 123, email: "test@example.com"}
    end

    test "extracts tenant from frame" do
      # Setup frame with tenant
      frame = %Frame{
        assigns: %{
          tenant: "tenant_123"
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert
      assert result[:tenant] == "tenant_123"
    end

    test "extracts context from frame" do
      # Setup frame with context
      frame = %Frame{
        assigns: %{
          context: %{org_id: 456, permissions: [:read, :write]}
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert
      assert result[:context] == %{org_id: 456, permissions: [:read, :write]}
    end

    test "extracts all three contexts together" do
      # Setup frame with all contexts
      frame = %Frame{
        assigns: %{
          actor: %{id: 123},
          tenant: "tenant_123",
          context: %{org_id: 456}
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert all are present
      assert result[:actor] == %{id: 123}
      assert result[:tenant] == "tenant_123"
      assert result[:context] == %{org_id: 456}
    end

    test "handles missing actor gracefully" do
      # Setup frame without actor
      frame = %Frame{assigns: %{}}

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert - should return keyword list with nil
      assert Keyword.has_key?(result, :actor)
      assert result[:actor] == nil
    end

    test "handles missing tenant gracefully" do
      # Setup frame without tenant
      frame = %Frame{assigns: %{}}

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert
      assert Keyword.has_key?(result, :tenant)
      assert result[:tenant] == nil
    end

    test "handles missing context with default empty map" do
      # Setup frame without context
      frame = %Frame{assigns: %{}}

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert - should default to empty map
      assert result[:context] == %{}
    end

    test "ignores other frame assigns" do
      # Setup frame with other assigns
      frame = %Frame{
        assigns: %{
          actor: %{id: 123},
          other_key: "should be ignored"
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert - only auth context is extracted
      assert Keyword.has_key?(result, :actor)
      refute Keyword.has_key?(result, :other_key)
    end

    test "returns keyword list format compatible with Ash.PlugHelpers" do
      # Setup frame
      frame = %Frame{
        assigns: %{
          actor: %{id: 123},
          tenant: "tenant_123",
          context: %{org_id: 456}
        }
      }

      # Act
      result = ContextMapper.from_frame(frame)

      # Assert - should be keyword list
      assert is_list(result)
      assert Keyword.keyword?(result)
    end
  end

  describe "roundtrip conversion" do
    test "to_frame -> from_frame preserves auth context" do
      # Original conn with all contexts using Ash.PlugHelpers
      conn =
        Plug.Test.conn(:get, "/")
        |> Ash.PlugHelpers.set_actor(%{id: 123, email: "test@example.com"})
        |> Ash.PlugHelpers.set_tenant("tenant_123")
        |> Ash.PlugHelpers.set_context(%{org_id: 456, permissions: [:read, :write]})

      # Convert conn -> frame -> keyword list
      frame = %Frame{assigns: %{}}
      frame = ContextMapper.to_frame(conn, frame)
      result = ContextMapper.from_frame(frame)

      # Assert all context preserved
      assert result[:actor] == %{id: 123, email: "test@example.com"}
      assert result[:tenant] == "tenant_123"
      assert result[:context] == %{org_id: 456, permissions: [:read, :write]}
    end
  end
end
