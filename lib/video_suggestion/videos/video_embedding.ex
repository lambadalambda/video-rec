defmodule VideoSuggestion.Videos.VideoEmbedding do
  use Ecto.Schema

  import Ecto.Changeset

  schema "video_embeddings" do
    field :version, :string
    field :vector, {:array, :float}

    belongs_to :video, VideoSuggestion.Videos.Video

    timestamps(type: :utc_datetime)
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:video_id, :version, :vector])
    |> validate_required([:video_id, :version, :vector])
    |> unique_constraint(:video_id)
  end
end

