defmodule Livellm.Memories.Tool do
  @moduledoc """
  Defines LlmComposer.Function tools for user memories.
  """

  alias Livellm.Memories

  @doc "Returns the list of LlmComposer.Function definitions for memory tools."
  def definitions do
    [
      %LlmComposer.Function{
        name: "get_user_memories",
        description:
          "Retrieve all stored user memories. Call this to recall facts or preferences about the user.",
        mf: {__MODULE__, :get_user_memories},
        schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      }
    ]
  end

  @doc false
  def get_user_memories(_args) do
    case Memories.list_memories() do
      [] ->
        "No memories stored."

      memories ->
        Enum.map_join(memories, "\n\n", fn m -> "### #{m.title}\n#{m.content}" end)
    end
  end
end
