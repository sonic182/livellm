defmodule Livellm.Tools.Registry do
  @moduledoc false

  alias Livellm.Tools.Definition
  alias Livellm.Tools.Markdown

  defmacro __using__(opts) do
    from = Keyword.fetch!(opts, :from)
    dir = Path.expand(from, Path.dirname(__CALLER__.file))
    definitions = load_definitions!(dir)
    external_resources = Enum.map(definitions, & &1.path)
    catalog = Enum.map(definitions, &catalog_entry/1)
    functions = Enum.map(definitions, &to_llm_function/1)

    external_resource_ast =
      Enum.map(external_resources, fn path ->
        quote do
          @external_resource unquote(path)
        end
      end)

    quote do
      unquote_splicing(external_resource_ast)

      @tool_catalog unquote(Macro.escape(catalog))
      @tool_definitions unquote(Macro.escape(functions))

      @spec catalog() :: [map()]
      def catalog, do: @tool_catalog

      @spec definitions() :: [LlmComposer.Function.t()]
      def definitions, do: @tool_definitions

      @spec enabled_definitions([String.t()]) :: [LlmComposer.Function.t()]
      def enabled_definitions(names) when is_list(names) do
        wanted = MapSet.new(names)
        Enum.filter(@tool_definitions, &MapSet.member?(wanted, &1.name))
      end

      @spec find_catalog_entry(String.t()) :: map() | nil
      def find_catalog_entry(name) when is_binary(name) do
        Enum.find(@tool_catalog, &(&1.name == name))
      end
    end
  end

  @spec load_definitions!(String.t()) :: [Definition.t()]
  defp load_definitions!(dir) do
    dir
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&Markdown.parse_file!/1)
    |> validate_unique_names!()
    |> Enum.map(&validate_mf!/1)
  end

  @spec validate_unique_names!([Definition.t()]) :: [Definition.t()]
  defp validate_unique_names!(definitions) do
    names = Enum.map(definitions, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> definitions
      [duplicate | _] -> raise ArgumentError, "duplicate tool name #{inspect(duplicate)}"
    end
  end

  @spec validate_mf!(Definition.t()) :: Definition.t()
  defp validate_mf!(%Definition{mf: {module, function}, path: path} = definition) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        unless function_exported?(module, function, 1) do
          raise ArgumentError, "tool #{path} points to missing #{inspect(module)}.#{function}/1"
        end

      {:error, reason} ->
        raise ArgumentError,
              "tool #{path} points to unavailable module #{inspect(module)}: #{inspect(reason)}"
    end

    definition
  end

  @spec catalog_entry(Definition.t()) :: map()
  defp catalog_entry(%Definition{} = definition) do
    %{
      name: definition.name,
      title: titleize(definition.name),
      description: definition.description,
      markdown: definition.markdown
    }
  end

  @spec to_llm_function(Definition.t()) :: LlmComposer.Function.t()
  defp to_llm_function(%Definition{} = definition) do
    %LlmComposer.Function{
      name: definition.name,
      description: definition.description,
      schema: definition.schema,
      mf: definition.mf
    }
  end

  @spec titleize(String.t()) :: String.t()
  defp titleize(name) do
    name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
