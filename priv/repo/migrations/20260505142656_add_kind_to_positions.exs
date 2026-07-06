defmodule CoinTracker.Repo.Migrations.AddKindToPositions do
  use Ecto.Migration

  def up do
    alter table(:positions) do
      add :kind, :string, null: false, default: "tracked"
    end

    # Watched positions (kind = :watched) intentionally have no stop-loss /
    # take-profit — they exist only to receive signal-based alerts. Drop the
    # NOT NULL constraint via raw SQL to avoid Ecto.Migration's `modify` +
    # `from:` reverse-spec ergonomics.
    execute("ALTER TABLE positions ALTER COLUMN stop_loss_percent DROP NOT NULL")
    execute("ALTER TABLE positions ALTER COLUMN take_profit_percent DROP NOT NULL")

    create index(:positions, [:user_id, :kind])

    # Race guard: a user can only have one active watch per symbol_price.
    # Partial index so it does not constrain real (tracked) positions.
    create unique_index(:positions, [:user_id, :symbol_price_id],
             where: "kind = 'watched'",
             name: :positions_watched_unique_per_user_symbol
           )
  end

  def down do
    drop index(:positions, [:user_id, :symbol_price_id],
           name: :positions_watched_unique_per_user_symbol
         )

    drop index(:positions, [:user_id, :kind])

    execute("ALTER TABLE positions ALTER COLUMN take_profit_percent SET NOT NULL")
    execute("ALTER TABLE positions ALTER COLUMN stop_loss_percent SET NOT NULL")

    alter table(:positions) do
      remove :kind
    end
  end
end
