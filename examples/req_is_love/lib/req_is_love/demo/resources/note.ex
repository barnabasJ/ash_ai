defmodule ReqIsLove.Demo.Note do
  @moduledoc """
  Note resource for the Demo domain.

  Provides note management with search capability.
  Uses ETS for in-memory persistence (suitable for demonstration).
  """

  use Ash.Resource,
    domain: ReqIsLove.Demo,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :body]
    end

    read :search do
      argument :query, :string do
        allow_nil? false
      end

      filter expr(contains(title, ^arg(:query)) or contains(body, ^arg(:query)))
    end
  end

  code_interface do
    define :create, args: [:title, :body]
    define :search, args: [:query]
    define :destroy
  end
end
