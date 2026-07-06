defmodule CoinTrackerWeb.Plugs.LocalePlug do
  @moduledoc """
  Plug to detect and set the locale for the request.

  Priority order:
  1. User's stored preference (from user_settings table)
  2. Session locale
  3. Accept-Language header
  4. Default to "en"
  """
  import Plug.Conn

  alias CoinTracker.Accounts

  @supported_locales ~w(en es)
  @default_locale "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = determine_locale(conn)

    Gettext.put_locale(CoinTrackerWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp determine_locale(conn) do
    # 1. Check user's stored preference
    user_locale = get_user_locale(conn)

    # 2. Check session
    session_locale = get_session(conn, :locale)

    # 3. Check Accept-Language header
    browser_locale = get_browser_locale(conn)

    # Return first valid locale or default
    cond do
      valid_locale?(user_locale) -> user_locale
      valid_locale?(session_locale) -> session_locale
      valid_locale?(browser_locale) -> browser_locale
      true -> @default_locale
    end
  end

  defp get_user_locale(conn) do
    case conn.assigns[:current_scope] do
      %{user: %{id: user_id}} when not is_nil(user_id) ->
        Accounts.get_user_locale(user_id)

      _ ->
        nil
    end
  end

  defp get_browser_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> parse_accept_language()
  end

  defp parse_accept_language([]), do: nil

  defp parse_accept_language([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(&parse_locale_tag/1)
    |> Enum.sort_by(fn {_locale, priority} -> -priority end)
    |> Enum.find_value(fn {locale, _} ->
      if valid_locale?(locale), do: locale
    end)
  end

  defp parse_locale_tag(tag) do
    [locale | rest] = String.split(String.trim(tag), ";")
    locale = locale |> String.split("-") |> hd() |> String.downcase()

    priority =
      case rest do
        ["q=" <> q | _] -> parse_quality(q)
        _ -> 1.0
      end

    {locale, priority}
  end

  defp parse_quality(q) do
    case Float.parse(q) do
      {value, _} -> value
      :error -> 1.0
    end
  end

  defp valid_locale?(nil), do: false
  defp valid_locale?(locale), do: locale in @supported_locales
end
