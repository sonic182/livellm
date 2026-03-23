defmodule Livellm.ChatsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Livellm.Chats` context.
  """

  @doc """
  Generate a chat.
  """
  def chat_fixture(attrs \\ %{}) do
    {:ok, chat} =
      attrs
      |> Enum.into(%{
        model: "some model",
        title: "some title"
      })
      |> Livellm.Chats.create_chat()

    chat
  end
end
