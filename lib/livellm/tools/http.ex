defmodule Livellm.Tools.Http do
  @moduledoc false

  @redirect_statuses [301, 302, 303, 307, 308]
  @allowed_methods ~w(GET POST PUT PATCH DELETE HEAD OPTIONS)

  @spec request(map()) :: String.t()
  def request(args) when is_map(args) do
    with {:ok, method} <- parse_method(Map.get(args, "method")),
         {:ok, url} <- parse_url(Map.get(args, "url")),
         {:ok, headers} <- parse_headers(Map.get(args, "headers", [])),
         {:ok, body, headers} <- build_body(Map.get(args, "body"), headers),
         {:ok, response} <- do_request(method, url, headers, body, config().max_redirects) do
      encode_response(response)
    else
      {:error, reason} -> "Error: #{reason}"
    end
  end

  def request(_args), do: "Error: request expects an object."

  @spec do_request(
          atom(),
          String.t(),
          [{String.t(), String.t()}],
          iodata() | nil,
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, String.t()}
  defp do_request(method, url, headers, body, redirects_left) do
    with :ok <- validate_url(url),
         {:ok, response} <- perform_request(method, url, headers, body) do
      maybe_follow_redirect(response, method, url, headers, body, redirects_left)
    end
  end

  @spec perform_request(atom(), String.t(), [{String.t(), String.t()}], iodata() | nil) ::
          {:ok, Finch.Response.t()} | {:error, String.t()}
  defp perform_request(method, url, headers, body) do
    request = Finch.build(method, url, headers, body)

    case Finch.request(request, config().finch_name,
           receive_timeout: config().receive_timeout,
           request_timeout: config().receive_timeout,
           connect_options: [timeout: config().connect_timeout]
         ) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, "request failed (#{inspect(reason)})"}
    end
  rescue
    e -> {:error, "request failed (#{Exception.message(e)})"}
  end

  @spec maybe_follow_redirect(
          Finch.Response.t(),
          atom(),
          String.t(),
          [{String.t(), String.t()}],
          iodata() | nil,
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, String.t()}
  defp maybe_follow_redirect(response, method, url, headers, body, redirects_left) do
    location = find_header(response.headers, "location")

    cond do
      response.status in @redirect_statuses and is_nil(location) ->
        {:ok, response_payload(response, url)}

      response.status in @redirect_statuses and redirects_left == 0 ->
        {:error, "too many redirects"}

      response.status in @redirect_statuses ->
        next_url = URI.merge(url, location) |> to_string()
        {next_method, next_body} = redirect_request_shape(response.status, method, body)
        do_request(next_method, next_url, headers, next_body, redirects_left - 1)

      true ->
        {:ok, response_payload(response, url)}
    end
  end

  @spec redirect_request_shape(non_neg_integer(), atom(), iodata() | nil) ::
          {atom(), iodata() | nil}
  defp redirect_request_shape(status, method, _body)
       when status in [301, 302, 303] and method not in [:get, :head] do
    {:get, nil}
  end

  defp redirect_request_shape(_status, method, body), do: {method, body}

  @spec response_payload(Finch.Response.t(), String.t()) :: map()
  defp response_payload(response, url) do
    {body, encoding, truncated} = normalize_response_body(response.body)

    %{
      "url" => url,
      "status" => response.status,
      "headers" => normalize_response_headers(response.headers),
      "body" => body,
      "encoding" => encoding,
      "truncated" => truncated
    }
  end

  @spec normalize_response_headers([{String.t(), String.t()}]) :: map()
  defp normalize_response_headers(headers) do
    Enum.reduce(headers, %{}, fn {name, value}, acc ->
      Map.update(acc, String.downcase(name), [value], &[value | &1])
    end)
    |> Map.new(fn {name, values} -> {name, Enum.reverse(values)} end)
  end

  @spec normalize_response_body(binary()) :: {String.t(), String.t(), boolean()}
  defp normalize_response_body(body) when is_binary(body) do
    max_bytes = config().max_response_bytes
    truncated = byte_size(body) > max_bytes
    limited = binary_part(body, 0, min(byte_size(body), max_bytes))

    if String.valid?(limited) do
      {limited, "utf-8", truncated}
    else
      {Base.encode64(limited), "base64", truncated}
    end
  end

  @spec encode_response(map()) :: String.t()
  defp encode_response(payload), do: Jason.encode!(payload)

  @spec parse_method(String.t() | nil) :: {:ok, atom()} | {:error, String.t()}
  defp parse_method(nil), do: {:ok, :get}

  defp parse_method(method) when is_binary(method) do
    normalized = String.upcase(method)

    if normalized in @allowed_methods do
      {:ok, normalized |> String.downcase() |> String.to_atom()}
    else
      {:error, "unsupported method #{inspect(method)}"}
    end
  end

  defp parse_method(_method), do: {:error, "method must be a string"}

  @spec parse_url(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_url(url) when is_binary(url) and url != "", do: {:ok, url}
  defp parse_url(_url), do: {:error, "url must be a non-empty string"}

  @spec parse_headers(list()) :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  defp parse_headers(headers) when is_list(headers) do
    headers
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case entry do
        %{"name" => name, "value" => value} when is_binary(name) and is_binary(value) ->
          {:cont, {:ok, acc ++ [{String.downcase(name), value}]}}

        _ ->
          {:halt, {:error, "headers must be a list of %{name, value} objects"}}
      end
    end)
  end

  defp parse_headers(_headers), do: {:error, "headers must be a list"}

  @spec build_body(term(), [{String.t(), String.t()}]) ::
          {:ok, iodata() | nil, [{String.t(), String.t()}]} | {:error, String.t()}
  defp build_body(nil, headers), do: {:ok, nil, headers}
  defp build_body(body, headers) when is_binary(body), do: {:ok, body, headers}

  defp build_body(body, headers) do
    encoded = Jason.encode!(body)

    headers =
      if Enum.any?(headers, fn {name, _value} -> name == "content-type" end) do
        headers
      else
        headers ++ [{"content-type", "application/json"}]
      end

    {:ok, encoded, headers}
  rescue
    Protocol.UndefinedError ->
      {:error, "body must be JSON-encodable, a string, or null"}
  end

  @spec validate_url(String.t()) :: :ok | {:error, String.t()}
  defp validate_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "url must use http or https"}

      is_nil(uri.host) or uri.host == "" ->
        {:error, "url must include a host"}

      true ->
        validate_host(uri.host)
    end
  end

  @spec validate_host(String.t()) :: :ok | {:error, String.t()}
  defp validate_host(host) do
    with {:ok, addresses} <- resolve_addresses(host),
         false <- blocked_address?(addresses) do
      :ok
    else
      true -> {:error, "destination IP is blocked by restricted_cidrs"}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec resolve_addresses(String.t()) :: {:ok, [tuple()]} | {:error, String.t()}
  defp resolve_addresses(host) do
    host_chars = String.to_charlist(host)

    case :inet.parse_address(host_chars) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _reason} ->
        ipv4 =
          case :inet.getaddrs(host_chars, :inet) do
            {:ok, addrs} -> addrs
            _ -> []
          end

        ipv6 =
          case :inet.getaddrs(host_chars, :inet6) do
            {:ok, addrs} -> addrs
            _ -> []
          end

        addresses = ipv4 ++ ipv6

        if addresses == [] do
          {:error, "could not resolve host"}
        else
          {:ok, addresses}
        end
    end
  end

  @spec blocked_address?([tuple()]) :: boolean()
  defp blocked_address?(addresses) do
    restricted = Enum.map(config().restricted_cidrs, &InetCidr.parse_cidr!/1)

    Enum.any?(addresses, fn address ->
      Enum.any?(restricted, &InetCidr.contains?(&1, address))
    end)
  end

  @spec find_header([{String.t(), String.t()}], String.t()) :: String.t() | nil
  defp find_header(headers, name) do
    normalized = String.downcase(name)

    Enum.find_value(headers, fn {header_name, value} ->
      if String.downcase(header_name) == normalized, do: value
    end)
  end

  @spec config() :: %{
          finch_name: atom(),
          connect_timeout: pos_integer(),
          receive_timeout: pos_integer(),
          max_response_bytes: pos_integer(),
          max_redirects: non_neg_integer(),
          restricted_cidrs: [String.t()]
        }
  defp config do
    livellm_config = Application.get_env(:livellm, __MODULE__, [])

    %{
      finch_name: Keyword.fetch!(livellm_config, :finch_name),
      connect_timeout: Keyword.fetch!(livellm_config, :connect_timeout),
      receive_timeout: Keyword.fetch!(livellm_config, :receive_timeout),
      max_response_bytes: Keyword.fetch!(livellm_config, :max_response_bytes),
      max_redirects: Keyword.fetch!(livellm_config, :max_redirects),
      restricted_cidrs: Keyword.fetch!(livellm_config, :restricted_cidrs)
    }
  end
end
