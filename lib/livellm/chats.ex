defmodule Livellm.Chats do
  @moduledoc """
  The Chats context.
  """

  import Ecto.Query, warn: false

  alias Livellm.Chats.Chat
  alias Livellm.Chats.Message
  alias Livellm.Repo

  # --- Chats ---

  def list_chats do
    Repo.all(from c in Chat, order_by: [desc: c.inserted_at])
  end

  def get_chat!(id), do: Repo.get!(Chat, id)

  def create_chat(attrs) do
    %Chat{}
    |> Chat.changeset(attrs)
    |> Repo.insert()
  end

  def update_chat(%Chat{} = chat, attrs) do
    chat
    |> Chat.changeset(attrs)
    |> Repo.update()
  end

  def delete_chat(%Chat{} = chat), do: Repo.delete(chat)

  def change_chat(%Chat{} = chat, attrs \\ %{}) do
    Chat.changeset(chat, attrs)
  end

  # --- Messages ---

  def list_messages(%Chat{} = chat) do
    Repo.all(from m in Message, where: m.chat_id == ^chat.id, order_by: m.inserted_at)
  end

  def create_message(%Chat{} = chat, attrs) do
    %Message{chat_id: chat.id}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def latest_assistant_message(%Chat{} = chat) do
    Repo.one(
      from m in Message,
        where: m.chat_id == ^chat.id and m.role == "assistant",
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: 1
    )
  end
end
