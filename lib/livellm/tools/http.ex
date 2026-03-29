defmodule Livellm.Tools.Http do
  @moduledoc false

  @allowed_methods ~w(GET POST PUT PATCH DELETE HEAD OPTIONS)
  @redirect_statuses [301, 302, 303, 307, 308]

  @type headers_t :: [{String.t(), String.t()}]
  @type body_t :: iodata() | nil

  @spec request(map()) :: String.t()
  def request(args) when is_map(args) do
    with {:ok, request_data} <- normalize_request(args),
         {:ok, payload} <- execute_request(request_data) do
      Jason.encode!(payload)
    else
      {:error, reason} ->
        error_message(reason)
    end
  end

  def request(_args), do: error_message("request expects an object")

  @spec normalize_request(map()) ::
          {:ok, %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()}}
          | {:error, String.t()}
  defp normalize_request(args) do
    with {:ok, method} <- parse_method(Map.get(args, "method")),
         {:ok, url} <- parse_url(Map.get(args, "url")),
         {:ok, headers} <- parse_headers(Map.get(args, "headers", [])),
         {:ok, body, normalized_headers} <- parse_body(Map.get(args, "body"), headers) do
      {:ok, %{method: method, url: url, headers: normalized_headers, body: body}}
    end
  end

  @spec execute_request(%{method: atom(), url: String.t(), headers: headers_t(), body: body_t()}) ::
          {:ok, map()} | {:error, String.t()}
  defp execute_request(request_data) do
    follow_request(request_data, config(:max_redirects))
  end

  @spec follow_request(
          %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()},
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, String.t()}
  defp follow_request(request_data, redirects_left) do
    with :ok <- validate_url(request_data.url),
         {:ok, response} <- send_request(request_data) do
      maybe_follow_redirect(response, request_data, redirects_left)
    end
  end

  @spec send_request(%{method: atom(), url: String.t(), headers: headers_t(), body: body_t()}) ::
          {:ok, Finch.Response.t()} | {:error, String.t()}
  defp send_request(request_data) do
    request =
      Finch.build(
        request_data.method,
        request_data.url,
        request_data.headers,
        request_data.body
      )

    case Finch.request(request, config(:finch_name), finch_request_opts()) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, "request failed (#{inspect(reason)})"}
    end
  rescue
    error ->
      {:error, "request failed (#{Exception.message(error)})"}
  end

  @spec maybe_follow_redirect(
          Finch.Response.t(),
          %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()},
          non_neg_integer()
        ) :: {:ok, map()} | {:error, String.t()}
  defp maybe_follow_redirect(response, request_data, redirects_left) do
    if response.status in @redirect_statuses do
      follow_redirect(response, request_data, redirects_left)
    else
      {:ok, build_response_payload(response, request_data.url)}
    end
  end

  @spec follow_redirect(
          Finch.Response.t(),
          %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()},
          non_neg_integer()
        ) :: {:ok, map()} | {:error, String.t()}
  defp follow_redirect(response, request_data, redirects_left) do
    with {:ok, next_url} <- redirect_url(response, request_data.url),
         :ok <- validate_redirect_limit(next_url, request_data.url, redirects_left) do
      request_data
      |> Map.put(:url, next_url)
      |> apply_redirect_method(response.status)
      |> follow_request(redirects_left - 1)
    end
  end

  @spec redirect_url(Finch.Response.t(), String.t()) :: {:ok, String.t()}
  defp redirect_url(response, current_url) do
    case find_header(response.headers, "location") do
      nil ->
        {:ok, current_url}

      location ->
        {:ok, URI.merge(current_url, location) |> to_string()}
    end
  end

  @spec validate_redirect_limit(String.t(), String.t(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  defp validate_redirect_limit(next_url, current_url, redirects_left) do
    if redirects_left == 0 and next_url != current_url do
      {:error, "too many redirects"}
    else
      :ok
    end
  end

  @spec apply_redirect_method(
          %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()},
          non_neg_integer()
        ) :: %{method: atom(), url: String.t(), headers: headers_t(), body: body_t()}
  defp apply_redirect_method(request_data, status)
       when status in [301, 302, 303] and request_data.method not in [:get, :head] do
    %{request_data | method: :get, body: nil}
  end

  defp apply_redirect_method(request_data, _status), do: request_data

  @spec build_response_payload(Finch.Response.t(), String.t()) :: map()
  defp build_response_payload(response, url) do
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

  @spec parse_method(String.t() | nil) :: {:ok, atom()} | {:error, String.t()}
  defp parse_method(nil), do: {:ok, :get}

  defp parse_method(method) when is_binary(method) do
    normalized_method = String.upcase(method)

    if normalized_method in @allowed_methods do
      {:ok, normalized_method |> String.downcase() |> String.to_atom()}
    else
      {:error, "unsupported method #{inspect(method)}"}
    end
  end

  defp parse_method(_method), do: {:error, "method must be a string"}

  @spec parse_url(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_url(url) when is_binary(url) and url != "", do: {:ok, url}
  defp parse_url(_url), do: {:error, "url must be a non-empty string"}

  @spec parse_headers(list()) :: {:ok, headers_t()} | {:error, String.t()}
  defp parse_headers(headers) when is_list(headers) do
    do_parse_headers(headers, [])
  end

  defp parse_headers(_headers), do: {:error, "headers must be a list"}

  @spec do_parse_headers(list(), headers_t()) :: {:ok, headers_t()} | {:error, String.t()}
  defp do_parse_headers([], headers), do: {:ok, Enum.reverse(headers)}

  defp do_parse_headers([header | rest], headers) do
    case parse_header(header) do
      {:ok, normalized_header} ->
        do_parse_headers(rest, [normalized_header | headers])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec parse_header(map()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  defp parse_header(%{"name" => name, "value" => value})
       when is_binary(name) and is_binary(value) do
    {:ok, {String.downcase(name), value}}
  end

  defp parse_header(_header), do: {:error, "headers must be a list of %{name, value} objects"}

  @spec parse_body(term(), headers_t()) :: {:ok, body_t(), headers_t()} | {:error, String.t()}
  defp parse_body(nil, headers), do: {:ok, nil, headers}
  defp parse_body(body, headers) when is_binary(body), do: {:ok, body, headers}

  defp parse_body(_body, _headers) do
    {:error, "body must be a string or null"}
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
    case resolve_addresses(host) do
      {:error, reason} ->
        {:error, reason}

      {:ok, addresses} ->
        if blocked_address?(addresses) do
          {:error, "destination IP is blocked by restricted_cidrs"}
        else
          :ok
        end
    end
  end

  @spec resolve_addresses(String.t()) :: {:ok, [tuple()]} | {:error, String.t()}
  defp resolve_addresses(host) do
    host_chars = String.to_charlist(host)

    case :inet.parse_address(host_chars) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _reason} ->
        resolve_host_addresses(host_chars)
    end
  end

  @spec resolve_host_addresses(charlist()) :: {:ok, [tuple()]} | {:error, String.t()}
  defp resolve_host_addresses(host_chars) do
    addresses =
      resolve_inet_addresses(host_chars, :inet) ++ resolve_inet_addresses(host_chars, :inet6)

    if addresses == [] do
      {:error, "could not resolve host"}
    else
      {:ok, addresses}
    end
  end

  @spec resolve_inet_addresses(charlist(), :inet | :inet6) :: [tuple()]
  defp resolve_inet_addresses(host_chars, family) do
    case :inet.getaddrs(host_chars, family) do
      {:ok, addresses} -> addresses
      {:error, _reason} -> []
    end
  end

  @spec blocked_address?([tuple()]) :: boolean()
  defp blocked_address?(addresses) do
    restricted_cidrs = Enum.map(config(:restricted_cidrs), &InetCidr.parse_cidr!/1)

    Enum.any?(addresses, fn address ->
      Enum.any?(restricted_cidrs, &InetCidr.contains?(&1, address))
    end)
  end

  @spec find_header(headers_t(), String.t()) :: String.t() | nil
  defp find_header(headers, name) do
    normalized_name = String.downcase(name)

    Enum.find_value(headers, fn {header_name, value} ->
      if String.downcase(header_name) == normalized_name do
        value
      end
    end)
  end

  @spec normalize_response_headers(headers_t()) :: map()
  defp normalize_response_headers(headers) do
    headers
    |> Enum.reduce(%{}, &append_response_header/2)
    |> Map.new(fn {name, values} -> {name, Enum.reverse(values)} end)
  end

  @spec append_response_header({String.t(), String.t()}, map()) :: map()
  defp append_response_header({name, value}, headers) do
    Map.update(headers, String.downcase(name), [value], &[value | &1])
  end

  @spec normalize_response_body(binary()) :: {String.t(), String.t(), boolean()}
  defp normalize_response_body(body) when is_binary(body) do
    max_response_bytes = config(:max_response_bytes)
    body_size = byte_size(body)
    truncated? = body_size > max_response_bytes
    limited_body = binary_part(body, 0, min(body_size, max_response_bytes))

    if String.valid?(limited_body) do
      {limited_body, "utf-8", truncated?}
    else
      {Base.encode64(limited_body), "base64", truncated?}
    end
  end

  @spec finch_request_opts() :: keyword()
  defp finch_request_opts do
    [
      receive_timeout: config(:receive_timeout),
      request_timeout: config(:receive_timeout),
      connect_options: [timeout: config(:connect_timeout)]
    ]
  end

  @spec config(atom()) :: term()
  defp config(key) do
    :livellm
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(key)
  end

  @spec error_message(String.t()) :: String.t()
  defp error_message(reason), do: "Error: #{reason}"
end
