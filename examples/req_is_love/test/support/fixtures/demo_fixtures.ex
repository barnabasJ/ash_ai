defmodule ReqIsLove.DemoFixtures do
  @moduledoc """
  Test data generators for Demo domain resources.

  Provides fixture functions to create test data for Task and Note resources.
  """

  @doc """
  Generates a task fixture.

  ## Parameters

    * `attrs` - Optional attributes to override defaults

  ## Examples

      iex> task_fixture()
      %ReqIsLove.Demo.Task{title: "Test Task", ...}

      iex> task_fixture(%{title: "Custom Task"})
      %ReqIsLove.Demo.Task{title: "Custom Task", ...}
  """
  def task_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "Test Task",
        description: "Test description"
      })

    {:ok, task} = ReqIsLove.Demo.Task.create(attrs.title, attrs[:description])
    task
  end

  @doc """
  Generates a note fixture.

  ## Parameters

    * `attrs` - Optional attributes to override defaults

  ## Examples

      iex> note_fixture()
      %ReqIsLove.Demo.Note{title: "Test Note", ...}

      iex> note_fixture(%{title: "Custom Note", body: "Custom body"})
      %ReqIsLove.Demo.Note{title: "Custom Note", body: "Custom body", ...}
  """
  def note_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "Test Note",
        body: "Test body"
      })

    {:ok, note} = ReqIsLove.Demo.Note.create(attrs.title, attrs.body)
    note
  end
end
