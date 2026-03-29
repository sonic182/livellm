defmodule Livellm.Tools.Markdown do
  @moduledoc false

  alias Livellm.Tools.Definition

  @front_matter_regex ~r/\A---\s*\n(?<front_matter>.*?)\n---\s*\n?(?<markdown>.*)\z/s

  @spec parse_file!(String.t()) :: Definition.t()
  def parse_file!(path) do
    path
    |> File.read!()
    |> parse!(path)
  end

  @spec parse!(String.t(), String.t()) :: Definition.t()
  def parse!(contents, path) when is_binary(contents) and is_binary(path) do
    %{"front_matter" => front_matter, "markdown" => markdown} =
      Regex.named_captures(@front_matter_regex, contents) ||
        raise ArgumentError, "missing YAML front matter in #{path}"

    attrs =
      front_matter
      |> YamlElixir.read_from_string!()
      |> stringify_map_keys()

    mf_attrs = Map.fetch!(attrs, "mf") |> stringify_map_keys()
    module = fetch_module!(mf_attrs, path)
    function = fetch_function!(mf_attrs, path)
    description = String.trim(markdown)

    %Definition{
      name: fetch_string!(attrs, "name", path),
      description:
        if description == "" do
          raise ArgumentError, "expected markdown body to provide a description in #{path}"
        else
          description
        end,
      schema: Map.fetch!(attrs, "schema") |> stringify_map_keys(),
      mf: {module, function},
      path: path,
      markdown: description
    }
  end

  @spec stringify_map_keys(term()) :: term()
  defp stringify_map_keys(%{} = map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_map_keys(value)}
    end)
  end

  defp stringify_map_keys(list) when is_list(list), do: Enum.map(list, &stringify_map_keys/1)
  defp stringify_map_keys(value), do: value

  @spec fetch_string!(map(), String.t(), String.t()) :: String.t()
  defp fetch_string!(attrs, key, path) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "expected #{key} to be a non-empty string in #{path}"
    end
  end

  @spec fetch_module!(map(), String.t()) :: module()
  defp fetch_module!(attrs, path) do
    attrs
    |> fetch_string!("module", path)
    |> String.split(".")
    |> Module.concat()
  end

  @spec fetch_function!(map(), String.t()) :: atom()
  defp fetch_function!(attrs, path) do
    attrs
    |> fetch_string!("function", path)
    |> String.to_atom()
  end
end
