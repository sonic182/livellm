defmodule Livellm.Chats.ActiveTasks do
  @moduledoc """
  Tracks which chat IDs have an active LLM task in progress.

  Uses a public ETS table so that reconnected LiveViews can check whether
  a task is still running for a given chat (e.g. after an F5 reload) and
  restore the loading indicator accordingly.
  """

  use GenServer

  @table :livellm_active_tasks

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec mark_active(integer()) :: :ok
  def mark_active(chat_id) do
    :ets.insert(@table, {chat_id})
    :ok
  end

  @spec mark_done(integer()) :: :ok
  def mark_done(chat_id) do
    :ets.delete(@table, chat_id)
    :ok
  end

  @spec active?(integer()) :: boolean()
  def active?(chat_id) do
    :ets.member(@table, chat_id)
  end

  @impl true
  def init([]) do
    :ets.new(@table, [:set, :public, :named_table])
    {:ok, []}
  end
end
