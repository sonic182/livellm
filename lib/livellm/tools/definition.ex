defmodule Livellm.Tools.Definition do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          schema: map(),
          mf: {module(), atom()},
          path: String.t(),
          markdown: String.t()
        }

  defstruct [:name, :description, :schema, :mf, :path, :markdown]
end
