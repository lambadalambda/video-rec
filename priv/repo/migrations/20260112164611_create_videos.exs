defmodule VideoSuggestion.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :caption, :text
      add :storage_key, :string, null: false
      add :original_filename, :string
      add :content_type, :string

      timestamps(type: :utc_datetime)
    end

    create index(:videos, [:user_id])
    create unique_index(:videos, [:storage_key])
  end
end
