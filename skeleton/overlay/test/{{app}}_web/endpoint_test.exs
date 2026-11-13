defmodule {{App}}Web.EndpointTest do
  # These settings are process-global application config, not per-request state.
  use ExUnit.Case, async: false

  alias {{App}}Web.Endpoint

  setup do
    session = Application.fetch_env(:{{app}}, :session)
    trust_proxy = Application.fetch_env(:{{app}}, :trust_proxy)

    on_exit(fn ->
      restore_env(:session, session)
      restore_env(:trust_proxy, trust_proxy)
    end)
  end

  test "session options follow application config after the endpoint was compiled" do
    Application.put_env(:{{app}}, :session,
      signing_salt: "test-signing-salt",
      encryption_salt: "test-encryption-salt",
      max_age: 123,
      secure: true
    )

    options = Endpoint.session_options()

    assert options[:signing_salt] == "test-signing-salt"
    assert options[:encryption_salt] == "test-encryption-salt"
    assert options[:max_age] == 123
    assert options[:secure]
    assert options[:store] == :cookie
    assert options[:key] == "_{{app}}_key"
    assert options[:http_only]
    assert options[:renew]
  end

  test "session config omits secure until SESSION_COOKIE_SECURE chooses it" do
    Application.put_env(:{{app}}, :session,
      signing_salt: "test-signing-salt",
      encryption_salt: "test-encryption-salt",
      max_age: 123
    )

    refute Keyword.has_key?(Endpoint.session_options(), :secure)
  end

  test "proxy headers are rewritten only after explicit opt-in" do
    Application.put_env(:{{app}}, :trust_proxy, false)
    assert Endpoint.rewrite_on() == []

    Application.put_env(:{{app}}, :trust_proxy, true)

    assert Endpoint.rewrite_on() == [
             :x_forwarded_for,
             :x_forwarded_proto,
             :x_forwarded_host,
             :x_forwarded_port
           ]
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:{{app}}, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:{{app}}, key)
end
