defmodule VideoSuggestion.Recommendations do
  @moduledoc """
  Glue code between the pure recommendation core (`VideoSuggestion.Reco.*`) and persistence.

  For now, we derive a taste vector from a user's favorited videos and rank other videos
  by dot-product similarity against stored `video_embeddings`.
  """

  import Ecto.Query, warn: false

  alias VideoSuggestion.Reco.Ranking
  alias VideoSuggestion.Reco.Vector
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos.Favorite
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Videos.VideoEmbedding

  @type score :: float()

  @spec taste_vector_from_favorites(integer()) ::
          {:ok, Vector.t()}
          | {:error, :empty | :empty_vector | :dimension_mismatch | :zero_norm}
  def taste_vector_from_favorites(user_id) when is_integer(user_id) do
    vectors =
      from(f in Favorite,
        join: e in VideoEmbedding,
        on: e.video_id == f.video_id,
        where: f.user_id == ^user_id,
        select: e.vector
      )
      |> Repo.all()

    case vectors do
      [] ->
        {:error, :empty}

      vectors ->
        with {:ok, mean} <- Vector.mean(vectors),
             {:ok, normalized} <- Vector.normalize(mean) do
          {:ok, normalized}
        end
    end
  end

  @spec rank_videos_for_user(integer(), keyword()) ::
          {:ok, [{integer(), score()}]}
          | {:error,
             :empty
             | :empty_vector
             | :dimension_mismatch
             | :zero_norm}
  def rank_videos_for_user(user_id, opts \\ []) when is_integer(user_id) do
    limit = Keyword.get(opts, :limit, 25)
    candidate_limit = Keyword.get(opts, :candidate_limit, 500)

    with {:ok, taste} <- taste_vector_from_favorites(user_id) do
      candidates = candidate_embeddings(user_id, candidate_limit)

      case Ranking.rank_by_dot(taste, candidates) do
        {:ok, scored} ->
          {:ok,
           scored
           |> Enum.take(limit)
           |> Enum.map(fn {candidate, score} -> {candidate.id, score} end)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp candidate_embeddings(user_id, limit) when is_integer(user_id) and is_integer(limit) do
    from(v in Video,
      join: e in VideoEmbedding,
      on: e.video_id == v.id,
      left_join: f in Favorite,
      on: f.video_id == v.id and f.user_id == ^user_id,
      where: is_nil(f.id),
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: ^limit,
      select: %{id: v.id, vector: e.vector}
    )
    |> Repo.all()
  end
end

