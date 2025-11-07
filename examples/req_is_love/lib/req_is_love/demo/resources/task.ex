defmodule ReqIsLove.Demo.Task do
  @moduledoc """
  Task resource for the Demo domain.

  Provides simple task management with CRUD operations.
  Uses ETS for in-memory persistence (suitable for demonstration).
  """

  use Ash.Resource,
    domain: ReqIsLove.Demo,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :completed, :boolean do
      default(false)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :description])
    end

    update :complete do
      accept([])
      change(set_attribute(:completed, true))

      change(fn changeset, _context ->
        IO.puts("\n=== COMPLETE ACTION CALLED ===")
        IO.puts("Changeset data: #{inspect(changeset.data)}")
        IO.puts("Changeset attributes: #{inspect(changeset.attributes)}")
        IO.puts("==============================\n")
        changeset
      end)
    end
  end

  code_interface do
    define(:list_all, action: :read)
    define(:create, args: [:title, :description])
    define(:complete)
    define(:destroy)
  end
end
