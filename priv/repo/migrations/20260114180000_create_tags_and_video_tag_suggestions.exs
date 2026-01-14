defmodule VideoSuggestion.Repo.Migrations.CreateTagsAndVideoTagSuggestions do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false
      add :version, :string
      add :vector, {:array, :float}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:name])
    create index(:tags, [:version])

    create table(:video_tag_suggestions) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      add :score, :float, null: false
      add :video_embedding_version, :string, null: false
      add :tag_embedding_version, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:video_tag_suggestions, [:video_id])
    create index(:video_tag_suggestions, [:tag_id])
    create index(:video_tag_suggestions, [:video_embedding_version])
    create unique_index(:video_tag_suggestions, [:video_id, :tag_id, :video_embedding_version])
  end
end
