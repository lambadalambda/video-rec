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
    current_user_id = Keyword.get(opts, :current_user_id)

    query =
      from v in Video,
        left_join: f in Favorite,
        on: f.video_id == v.id,
        group_by: v.id,
        order_by: [desc: v.inserted_at, desc: v.id],
        limit: ^limit,
        select_merge: %{favorites_count: count(f.id)}

    query =
      if is_integer(current_user_id) do
        from [v, f] in query,
          select_merge: %{
            favorited:
              fragment(
                "COALESCE(BOOL_OR(? = ?), FALSE)",
                f.user_id,
                ^current_user_id
              )
          }
      else
        from [v, _f] in query,
          select_merge: %{favorited: false}
      end

    Repo.all(query)
  end

  def get_video!(id), do: Repo.get!(Video, id)

  def create_video(attrs) do
    %Video{}
    |> Video.changeset(attrs)
    |> Repo.insert()
  end

  def content_hash_exists?(content_hash) when is_binary(content_hash) do
    Repo.exists?(from v in Video, where: v.content_hash == ^content_hash)
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
