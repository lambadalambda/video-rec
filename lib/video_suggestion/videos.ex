defmodule VideoSuggestion.Videos do
  @moduledoc """
  The Videos context.
  """

  import Ecto.Query, warn: false

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Reco.CaptionEmbedding
  alias VideoSuggestion.Reco.DeterministicEmbedding
  alias VideoSuggestion.Videos.Favorite
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Videos.VideoEmbedding
  alias Ecto.Multi

  def list_videos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    current_user_id = Keyword.get(opts, :current_user_id)
    before = Keyword.get(opts, :before)

    query =
      from v in Video,
        left_join: f in Favorite,
        on: f.video_id == v.id,
        group_by: v.id,
        order_by: [desc: v.inserted_at, desc: v.id],
        limit: ^limit,
        select_merge: %{favorites_count: count(f.id)}

    query =
      case before do
        {before_inserted_at, before_id}
        when not is_nil(before_inserted_at) and is_integer(before_id) ->
          from v in query,
            where:
              v.inserted_at < ^before_inserted_at or
                (v.inserted_at == ^before_inserted_at and v.id < ^before_id)

        _ ->
          query
      end

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

  def list_tail_videos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    current_user_id = Keyword.get(opts, :current_user_id)

    tail_ids =
      from v in Video,
        order_by: [asc: v.inserted_at, asc: v.id],
        limit: ^limit,
        select: v.id

    query =
      from v in Video,
        where: v.id in subquery(tail_ids),
        left_join: f in Favorite,
        on: f.video_id == v.id,
        group_by: v.id,
        order_by: [desc: v.inserted_at, desc: v.id],
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

  def get_video_embedding!(video_id) when is_integer(video_id) do
    Repo.get_by!(VideoEmbedding, video_id: video_id)
  end

  def upsert_video_embedding(video_id, version, vector)
      when is_integer(video_id) and is_binary(version) and is_list(vector) do
    %VideoEmbedding{}
    |> VideoEmbedding.changeset(%{video_id: video_id, version: version, vector: vector})
    |> Repo.insert(
      conflict_target: :video_id,
      on_conflict: {:replace, [:version, :vector, :updated_at]}
    )
  end

  def set_video_transcript(video_id, transcript)
      when is_integer(video_id) and is_binary(transcript) do
    video = get_video!(video_id)

    video
    |> Video.transcript_changeset(%{transcript: transcript})
    |> Repo.update()
  end

  def create_video(attrs) do
    Multi.new()
    |> Multi.insert(:video, Video.changeset(%Video{}, attrs))
    |> Multi.run(:embedding, fn _repo, %{video: video} ->
      create_video_embedding(video)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{video: video}} -> {:ok, video}
      {:error, :video, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
      {:error, :embedding, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
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

  defp create_video_embedding(%Video{} = video) do
    caption = video.caption || ""

    {vector, version} =
      case CaptionEmbedding.embed(caption) do
        {:ok, v} ->
          {v, "caption_v1"}

        {:error, _} ->
          {DeterministicEmbedding.from_seed(video.content_hash), "hash_v1"}
      end

    %VideoEmbedding{}
    |> VideoEmbedding.changeset(%{video_id: video.id, version: version, vector: vector})
    |> Repo.insert()
  end
end
