defmodule VideoSuggestion.Repo.Migrations.ResizeVectorsTo1536AndAddHnswIndexes do
  use Ecto.Migration

  @dims 1536

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    drop_if_exists(index(:video_embeddings, [:version]))
    drop_if_exists(unique_index(:video_embeddings, [:video_id]))
    drop_if_exists(table(:video_embeddings))

    create table(:video_embeddings) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :vector, :vector, size: @dims, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:video_embeddings, [:video_id])
    create index(:video_embeddings, [:version])
    execute("CREATE INDEX video_embeddings_vector_hnsw_idx ON video_embeddings USING hnsw (vector vector_cosine_ops)")

    drop_if_exists(index(:video_tag_suggestions, [:video_embedding_version]))
    drop_if_exists(index(:video_tag_suggestions, [:tag_id]))
    drop_if_exists(index(:video_tag_suggestions, [:video_id]))
    drop_if_exists(unique_index(:video_tag_suggestions, [:video_id, :tag_id, :video_embedding_version]))
    drop_if_exists(table(:video_tag_suggestions))

    drop_if_exists(index(:tags, [:version]))
    drop_if_exists(unique_index(:tags, [:name]))
    drop_if_exists(table(:tags))

    create table(:tags) do
      add :name, :string, null: false
      add :version, :string
      add :vector, :vector, size: @dims

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:name])
    create index(:tags, [:version])
    execute("CREATE INDEX tags_vector_hnsw_idx ON tags USING hnsw (vector vector_cosine_ops) WHERE vector IS NOT NULL")

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

  def down do
    raise Ecto.MigrationError, "irreversible migration"
  end
end

