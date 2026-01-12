defmodule VideoSuggestion.Videos.Favorite do
  use Ecto.Schema

  import Ecto.Changeset

  schema "favorites" do
    belongs_to :user, VideoSuggestion.Accounts.User
    belongs_to :video, VideoSuggestion.Videos.Video

    timestamps(type: :utc_datetime)
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :video_id])
    |> validate_required([:user_id, :video_id])
    |> unique_constraint(:user_id, name: :favorites_user_id_video_id_index)
  end
end
