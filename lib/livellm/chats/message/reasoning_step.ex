defmodule Livellm.Chats.Message.ReasoningStep do
  @moduledoc """
  Schema for a single reasoning step in the AI's thought process.
  """

  @type t :: %{
          type: :reasoning | :tool_call,
          content: String.t() | nil,
          tool_name: String.t() | nil,
          status: :running | :completed | nil,
          timestamp: integer()
        }

  @doc """
  Creates a reasoning step.

  ## Examples

      iex> ReasoningStep.reasoning("Let me think about this...")
      %{type: :reasoning, content: "Let me think about this...", tool_name: nil, status: nil, timestamp: 1234567890}

  """
  @spec reasoning(String.t()) :: t()
  def reasoning(content) do
    %{
      type: :reasoning,
      content: content,
      tool_name: nil,
      status: nil,
      timestamp: System.system_time(:millisecond)
    }
  end

  @doc """
  Creates a tool call step.

  ## Examples

      iex> ReasoningStep.tool_call("get_logs", :running)
      %{type: :tool_call, content: nil, tool_name: "get_logs", status: :running, timestamp: 1234567890}

  """
  @spec tool_call(String.t(), :running | :completed) :: t()
  def tool_call(name, status) do
    %{
      type: :tool_call,
      content: nil,
      tool_name: name,
      status: status,
      timestamp: System.system_time(:millisecond)
    }
  end

  @doc """
  Updates a step's status.
  """
  @spec update_status(t(), :running | :completed) :: t()
  def update_status(step, status) do
    %{step | status: status}
  end
end
