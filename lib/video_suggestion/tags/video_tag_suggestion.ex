defmodule VideoSuggestion.Tags.VideoTagSuggestion do
  use Ecto.Schema

  import Ecto.Changeset

  schema "video_tag_suggestions" do
    field :score, :float
    field :video_embedding_version, :string
    field :tag_embedding_version, :string

    belongs_to :video, VideoSuggestion.Videos.Video
    belongs_to :tag, VideoSuggestion.Tags.Tag

    timestamps(type: :utc_datetime)
  end

  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [
      :video_id,
      :tag_id,
      :score,
      :video_embedding_version,
      :tag_embedding_version
    ])
    |> validate_required([
      :video_id,
      :tag_id,
      :score,
      :video_embedding_version,
      :tag_embedding_version
    ])
    |> unique_constraint([:video_id, :tag_id, :video_embedding_version])
  end
end
