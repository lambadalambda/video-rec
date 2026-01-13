defmodule VideoSuggestion.Videos.Video do
  use Ecto.Schema

  import Ecto.Changeset

  schema "videos" do
    field :caption, :string
    field :content_hash, :binary
    field :content_type, :string
    field :favorited, :boolean, virtual: true, default: false
    field :favorites_count, :integer, virtual: true, default: 0
    field :original_filename, :string
    field :storage_key, :string
    field :transcript, :string

    has_many :favorites, VideoSuggestion.Videos.Favorite

    belongs_to :user, VideoSuggestion.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :user_id,
      :caption,
      :storage_key,
      :original_filename,
      :content_type,
      :content_hash,
      :transcript
    ])
    |> validate_required([:user_id, :storage_key, :content_hash])
    |> unique_constraint(:storage_key)
    |> unique_constraint(:content_hash)
  end

  def transcript_changeset(video, attrs) do
    video
    |> cast(attrs, [:transcript])
  end
end
