defmodule VideoSuggestion.Recommendations do
  @moduledoc """
  Glue code between the pure recommendation core (`VideoSuggestion.Reco.*`) and persistence.

  For now, we derive a taste vector from a user's favorited videos and rank other videos
  by dot-product similarity against stored `video_embeddings`.
  """

  import Ecto.Query, warn: false

  alias VideoSuggestion.Reco.Ranking
  alias VideoSuggestion.Reco.TasteProfile
  alias VideoSuggestion.Reco.Vector
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Interactions.Interaction
  alias VideoSuggestion.Videos.Favorite
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Videos.VideoEmbedding

  @type score :: float()

  @spec taste_vector(integer(), keyword()) ::
          {:ok, Vector.t()}
          | {:error,
             :empty
             | :empty_vector
             | :dimension_mismatch
             | :invalid_alpha
             | :invalid_gamma
             | :invalid_max_gamma
             | :invalid_prior
             | :invalid_weight
             | :zero_norm}
  def taste_vector(user_id, opts \\ []) when is_integer(user_id) do
    profile =
      TasteProfile.new()
      |> apply_favorite_long_term(user_id, opts)
      |> apply_recent_watch_session(user_id, opts)

    TasteProfile.blended_vector(profile)
  end

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

    with {:ok, taste} <- taste_vector(user_id, opts) do
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

  @spec ranked_feed_video_ids_for_user(integer(), keyword()) ::
          {:ok, [integer()]}
          | {:error,
             :empty
             | :empty_vector
             | :dimension_mismatch
             | :zero_norm}
  def ranked_feed_video_ids_for_user(user_id, opts \\ []) when is_integer(user_id) do
    candidate_limit = Keyword.get(opts, :candidate_limit)
    diversify_pool_size = Keyword.get(opts, :diversify_pool_size, 200)
    diversify_lambda = Keyword.get(opts, :diversify_lambda, 0.7)

    with {:ok, taste} <- taste_vector(user_id, opts) do
      dim = length(taste)

      candidates =
        candidate_embeddings(user_id, candidate_limit)
        |> Enum.reject(fn candidate ->
          candidate.vector == [] or length(candidate.vector) != dim
        end)

      if candidates == [] do
        {:error, :empty}
      else
        case Ranking.rank_by_dot(taste, candidates) do
          {:ok, scored} ->
            ranked = Enum.map(scored, fn {candidate, _score} -> candidate end)

            {pool, rest} =
              if is_integer(diversify_pool_size) and diversify_pool_size > 0 do
                Enum.split(ranked, diversify_pool_size)
              else
                {[], ranked}
              end

            ranked =
              case pool do
                [] ->
                  ranked

                pool ->
                  case Ranking.mmr(taste, pool, length(pool), lambda: diversify_lambda) do
                    {:ok, diverse} -> diverse ++ rest
                    {:error, _reason} -> ranked
                  end
              end

            {:ok, Enum.map(ranked, & &1.id)}

          {:error, reason} ->
            {:error, reason}
        end
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

  defp candidate_embeddings(user_id, nil) when is_integer(user_id) do
    from(v in Video,
      join: e in VideoEmbedding,
      on: e.video_id == v.id,
      left_join: f in Favorite,
      on: f.video_id == v.id and f.user_id == ^user_id,
      where: is_nil(f.id),
      order_by: [desc: v.inserted_at, desc: v.id],
      select: %{id: v.id, vector: e.vector}
    )
    |> Repo.all()
  end

  defp apply_favorite_long_term(profile, user_id, opts) do
    weight = Keyword.get(opts, :favorite_weight, 2.0)

    vectors =
      from(f in Favorite,
        join: e in VideoEmbedding,
        on: e.video_id == f.video_id,
        where: f.user_id == ^user_id,
        select: e.vector
      )
      |> Repo.all()

    Enum.reduce_while(vectors, profile, fn vector, profile ->
      case TasteProfile.update_long(profile, vector, weight) do
        {:ok, profile} -> {:cont, profile}
        {:error, _reason} -> {:halt, profile}
      end
    end)
  end

  defp apply_recent_watch_session(profile, user_id, opts) do
    limit = Keyword.get(opts, :watch_limit, 50)
    alpha = Keyword.get(opts, :watch_alpha, 0.3)

    rows =
      from(i in Interaction,
        join: e in VideoEmbedding,
        on: e.video_id == i.video_id,
        where: i.user_id == ^user_id and i.event_type == "watch",
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: ^limit,
        select: {e.vector, i.watch_ms}
      )
      |> Repo.all()

    Enum.reduce_while(rows, profile, fn {vector, watch_ms}, profile ->
      weight = watch_weight(watch_ms, opts)

      case TasteProfile.update_session(profile, vector, alpha, weight) do
        {:ok, profile} -> {:cont, profile}
        {:error, _reason} -> {:halt, profile}
      end
    end)
  end

  defp watch_weight(watch_ms, opts) when is_integer(watch_ms) and watch_ms >= 0 do
    scale_ms = Keyword.get(opts, :watch_scale_ms, 1_000)
    max_weight = Keyword.get(opts, :max_watch_weight, 30.0)

    weight = watch_ms / max(scale_ms, 1)
    min(weight * 1.0, max_weight * 1.0)
  end

  defp watch_weight(_watch_ms, _opts), do: 1.0
end
