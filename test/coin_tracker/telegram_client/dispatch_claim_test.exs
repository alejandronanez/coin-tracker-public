defmodule CoinTracker.TelegramClient.DispatchClaimTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.TelegramClient.DispatchClaim

  # Pin the bucket within a test by stuffing the unix-second override into the
  # process dictionary that `DispatchClaim.current_bucket/0` consults. Tests
  # that need bucket transitions advance this value past `window_seconds`.
  defp pin_now(unix_seconds), do: Process.put(:dispatch_claim_now_override, unix_seconds)

  describe "claim/4" do
    test "returns :ok on first call" do
      pin_now(1_000_000)

      assert :ok = DispatchClaim.claim(unique_user_id(), "fp1234567890", "did12345", :test)
    end

    test "returns :duplicate on identical second call within the same window" do
      pin_now(1_000_000)
      user_id = unique_user_id()

      assert :ok = DispatchClaim.claim(user_id, "fpabcabcabc1", "did00001", :test)
      assert :duplicate = DispatchClaim.claim(user_id, "fpabcabcabc1", "did00002", :test)
    end

    test "different users with same fingerprint are not duplicates" do
      pin_now(1_000_000)

      assert :ok = DispatchClaim.claim(unique_user_id(), "fpsame000001", "did00001", :test)
      assert :ok = DispatchClaim.claim(unique_user_id(), "fpsame000001", "did00002", :test)
    end

    test "different fingerprints for same user are not duplicates" do
      pin_now(1_000_000)
      user_id = unique_user_id()

      assert :ok = DispatchClaim.claim(user_id, "fpaaaaaaaaa1", "did00001", :test)
      assert :ok = DispatchClaim.claim(user_id, "fpbbbbbbbbb1", "did00002", :test)
    end

    test "same triple succeeds again after the window bucket rolls over" do
      window = DispatchClaim.window_seconds()
      user_id = unique_user_id()

      pin_now(1_000_000)
      assert :ok = DispatchClaim.claim(user_id, "fproll123456", "did00001", :test)

      # Advance into the next bucket
      pin_now(1_000_000 + window)
      assert :ok = DispatchClaim.claim(user_id, "fproll123456", "did00002", :test)
    end

    test "stores the winning dispatch_id and notification_kind" do
      pin_now(1_000_000)
      user_id = unique_user_id()

      assert :ok = DispatchClaim.claim(user_id, "fpstored0001", "winnr001", :position_recovery)

      assert :duplicate =
               DispatchClaim.claim(user_id, "fpstored0001", "loser001", :position_recovery)

      [row] = Repo.all(DispatchClaim)
      assert row.dispatch_id == "winnr001"
      assert row.notification_kind == "position_recovery"
    end
  end

  describe "prune/1" do
    test "deletes rows older than the cutoff and leaves fresh rows" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -3600, :second)

      Repo.insert!(%DispatchClaim{
        user_id: unique_user_id(),
        fingerprint: "fpold0000001",
        window_bucket: 1,
        dispatch_id: "old00001",
        notification_kind: "test",
        inserted_at: old
      })

      Repo.insert!(%DispatchClaim{
        user_id: unique_user_id(),
        fingerprint: "fpnew0000001",
        window_bucket: 2,
        dispatch_id: "new00001",
        notification_kind: "test",
        inserted_at: now
      })

      assert {:ok, 1} = DispatchClaim.prune(60)
      assert [remaining] = Repo.all(DispatchClaim)
      assert remaining.fingerprint == "fpnew0000001"
    end
  end

  defp unique_user_id, do: System.unique_integer([:positive])
end
