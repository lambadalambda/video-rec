defmodule VideoSuggestion.Repo.Migrations.CreateFavorites do
  use Ecto.Migration

  def change do
    create table(:favorites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :video_id, references(:videos, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:favorites, [:user_id, :video_id])
    create index(:favorites, [:video_id])
    create index(:favorites, [:user_id])
  end
end
