defmodule VideoSuggestion.Repo.Migrations.CreateInteractions do
  use Ecto.Migration

  def change do
    create table(:interactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :watch_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:interactions, [:user_id])
    create index(:interactions, [:video_id])
    create index(:interactions, [:event_type])
    create index(:interactions, [:inserted_at])

    create constraint(:interactions, :watch_ms_non_negative,
             check: "watch_ms IS NULL OR watch_ms >= 0"
           )
  end
end
