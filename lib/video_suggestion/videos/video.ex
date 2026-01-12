defmodule VideoSuggestion.Videos.Video do
  use Ecto.Schema

  import Ecto.Changeset

  schema "videos" do
    field :caption, :string
    field :content_type, :string
    field :original_filename, :string
    field :storage_key, :string

    belongs_to :user, VideoSuggestion.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(video, attrs) do
    video
    |> cast(attrs, [:user_id, :caption, :storage_key, :original_filename, :content_type])
    |> validate_required([:user_id, :storage_key])
    |> unique_constraint(:storage_key)
  end
end
