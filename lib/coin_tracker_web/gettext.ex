defmodule CoinTrackerWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext), your module compiles translations
  that you can use in your application. To use this Gettext backend module,
  call `use Gettext` and pass it as an option:

      use Gettext, backend: CoinTrackerWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext.Backend, otp_app: :coin_tracker

  @doc """
  Translates a message, handling both string and tuple formats.

  Backpex calls this function with a tuple `{msgid, bindings}` when
  interpolation is needed, so we handle both formats here.
  """
  def gettext({msgid, bindings}) when is_binary(msgid) and is_map(bindings) do
    Gettext.gettext(__MODULE__, msgid, bindings)
  end

  def gettext(msgid) when is_binary(msgid) do
    Gettext.gettext(__MODULE__, msgid)
  end
end
