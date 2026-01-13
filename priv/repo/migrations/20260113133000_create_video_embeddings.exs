defmodule VideoSuggestion.Repo.Migrations.CreateVideoEmbeddings do
  use Ecto.Migration

  def change do
    create table(:video_embeddings) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :vector, {:array, :float}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:video_embeddings, [:video_id])
    create index(:video_embeddings, [:version])
  end
end

