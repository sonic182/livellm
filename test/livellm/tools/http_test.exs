defmodule Livellm.Tools.HttpTest do
  use ExUnit.Case, async: false

  alias Livellm.Tools.Http

  setup do
    previous = Application.get_env(:livellm, Livellm.Tools.Http)

    on_exit(fn ->
      Application.put_env(:livellm, Livellm.Tools.Http, previous)
    end)

    :ok
  end

  test "returns a JSON payload for a successful GET request" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/ok", fn conn ->
      Plug.Conn.resp(conn, 200, "hello world")
    end)

    Application.put_env(:livellm, Livellm.Tools.Http,
      finch_name: Livellm.ToolFinch,
      connect_timeout: 15_000,
      receive_timeout: 30_000,
      max_response_bytes: 200_000,
      max_redirects: 3,
      restricted_cidrs: []
    )

    result = Http.request(%{"url" => "http://localhost:#{bypass.port}/ok"})
    payload = Jason.decode!(result)

    assert payload["status"] == 200
    assert payload["body"] == "hello world"
    assert payload["encoding"] == "utf-8"
    refute payload["truncated"]
  end

  test "follows redirects and truncates large response bodies" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/redirect", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/final")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect_once(bypass, "GET", "/final", fn conn ->
      Plug.Conn.resp(conn, 200, String.duplicate("a", 10))
    end)

    Application.put_env(:livellm, Livellm.Tools.Http,
      finch_name: Livellm.ToolFinch,
      connect_timeout: 15_000,
      receive_timeout: 30_000,
      max_response_bytes: 4,
      max_redirects: 3,
      restricted_cidrs: []
    )

    result = Http.request(%{"url" => "http://localhost:#{bypass.port}/redirect"})
    payload = Jason.decode!(result)

    assert payload["status"] == 200
    assert payload["body"] == "aaaa"
    assert payload["truncated"]
  end

  test "returns redirect payloads without retrying when location is missing" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/redirect", fn conn ->
      Plug.Conn.resp(conn, 302, "redirect body")
    end)

    Application.put_env(:livellm, Livellm.Tools.Http,
      finch_name: Livellm.ToolFinch,
      connect_timeout: 15_000,
      receive_timeout: 30_000,
      max_response_bytes: 200_000,
      max_redirects: 3,
      restricted_cidrs: []
    )

    result = Http.request(%{"url" => "http://localhost:#{bypass.port}/redirect"})
    payload = Jason.decode!(result)

    assert payload["status"] == 302
    assert payload["body"] == "redirect body"
  end

  test "blocks requests whose destination matches a restricted cidr" do
    Application.put_env(:livellm, Livellm.Tools.Http,
      finch_name: Livellm.ToolFinch,
      connect_timeout: 15_000,
      receive_timeout: 30_000,
      max_response_bytes: 200_000,
      max_redirects: 3,
      restricted_cidrs: ["127.0.0.0/8"]
    )

    assert Http.request(%{"url" => "http://127.0.0.1/test"}) ==
             "Error: destination IP is blocked by restricted_cidrs"
  end
end
