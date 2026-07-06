defmodule CoinTracker.Repo.Migrations.DropFunWithFlagsTable do
  use Ecto.Migration

  def up do
    drop_if_exists index(:fun_with_flags_toggles, [:flag_name],
                     name: :fun_with_flags_toggles_flag_name_index
                   )

    drop_if_exists unique_index(:fun_with_flags_toggles, [:flag_name, :gate_type, :target],
                     name: :fwf_flag_name_gate_target_idx
                   )

    drop_if_exists table(:fun_with_flags_toggles)
  end

  def down do
    create table(:fun_with_flags_toggles, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end

    create index(:fun_with_flags_toggles, [:flag_name])

    create unique_index(
             :fun_with_flags_toggles,
             [:flag_name, :gate_type, :target],
             name: :fwf_flag_name_gate_target_idx
           )
  end
end
