defmodule CoinTracker.Branding do
  @moduledoc """
  Centralizes the deployment's public identity (app name, contact emails) so
  that no brand- or owner-specific values live in the source tree.

  Every value is read from configuration that `config/runtime.exs` populates
  from required environment variables (see `.env.example`). Reads use
  `Application.fetch_env!/2`, so a missing value raises at boot instead of
  silently shipping a placeholder.
  """

  @doc "Public application/brand name (env `APP_NAME`)."
  def app_name, do: fetch!(:app_name)

  @doc "Display name used as the outgoing-email sender (defaults to `app_name/0`)."
  def sender_name, do: app_name()

  @doc "\"From\" address for outgoing mail (env `SENDER_EMAIL`)."
  def sender_email, do: fetch!(:sender_email)

  @doc "Public support address shown to users (env `SUPPORT_EMAIL`)."
  def support_email, do: fetch!(:support_email)

  @doc "Internal recipient for owner notifications (env `ADMIN_NOTIFICATION_EMAIL`)."
  def admin_email, do: fetch!(:admin_notification_email)

  defp fetch!(key), do: Application.fetch_env!(:coin_tracker, key)
end
