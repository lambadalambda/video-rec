defmodule VideoSuggestion.Videos do
  @moduledoc """
  The Videos context.
  """

  import Ecto.Query, warn: false

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos.Favorite
  alias VideoSuggestion.Videos.Video

  def list_videos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Video
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_video!(id), do: Repo.get!(Video, id)

  def create_video(attrs) do
    %Video{}
    |> Video.changeset(attrs)
    |> Repo.insert()
  end

  def favorited?(user_id, video_id) when is_integer(user_id) and is_integer(video_id) do
    Repo.exists?(
      from f in Favorite,
        where: f.user_id == ^user_id and f.video_id == ^video_id
    )
  end

  def favorites_count(video_id) when is_integer(video_id) do
    Repo.aggregate(from(f in Favorite, where: f.video_id == ^video_id), :count, :id)
  end

  def toggle_favorite(user_id, video_id) when is_integer(user_id) and is_integer(video_id) do
    Repo.transaction(fn ->
      case Repo.get_by(Favorite, user_id: user_id, video_id: video_id) do
        %Favorite{} = favorite ->
          {:ok, _} = Repo.delete(favorite)

          %{
            favorited: false,
            favorites_count: favorites_count(video_id)
          }

        nil ->
          {:ok, _favorite} =
            %Favorite{}
            |> Favorite.changeset(%{user_id: user_id, video_id: video_id})
            |> Repo.insert()

          %{
            favorited: true,
            favorites_count: favorites_count(video_id)
          }
      end
    end)
  end
end
