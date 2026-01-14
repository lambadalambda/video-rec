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
      |> Enum.map(&as_list_vector/1)

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

    with {:ok, taste} <- taste_vector(user_id, opts) do
      taste_vec = Pgvector.new(taste)

      rows =
        from(v in Video,
          join: e in VideoEmbedding,
          on: e.video_id == v.id,
          left_join: f in Favorite,
          on: f.video_id == v.id and f.user_id == ^user_id,
          where: is_nil(f.id),
          order_by: fragment("? <=> ?", e.vector, ^taste_vec),
          limit: ^limit,
          select: {v.id, fragment("1 - (? <=> ?)", e.vector, ^taste_vec)}
        )
        |> Repo.all()

      {:ok, rows}
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
      taste_vec = Pgvector.new(taste)

      candidates_query =
        from(v in Video,
          join: e in VideoEmbedding,
          on: e.video_id == v.id,
          left_join: f in Favorite,
          on: f.video_id == v.id and f.user_id == ^user_id,
          where: is_nil(f.id),
          order_by: fragment("? <=> ?", e.vector, ^taste_vec),
          select: %{id: v.id, vector: e.vector}
        )

      candidates_query =
        if is_integer(candidate_limit) and candidate_limit > 0 do
          from(c in candidates_query, limit: ^candidate_limit)
        else
          candidates_query
        end

      candidates = Repo.all(candidates_query)

      if candidates == [] do
        {:error, :empty}
      else
        {pool, rest} =
          if is_integer(diversify_pool_size) and diversify_pool_size > 0 do
            Enum.split(candidates, diversify_pool_size)
          else
            {[], candidates}
          end

        ranked_ids =
          case pool do
            [] ->
              Enum.map(candidates, & &1.id)

            pool ->
              pool =
                Enum.map(pool, fn %{id: id, vector: vector} ->
                  %{id: id, vector: as_list_vector(vector)}
                end)

              case Ranking.mmr(taste, pool, length(pool), lambda: diversify_lambda) do
                {:ok, diverse} ->
                  Enum.map(diverse, & &1.id) ++ Enum.map(rest, & &1.id)

                {:error, _reason} ->
                  Enum.map(candidates, & &1.id)
              end
          end

        {:ok, ranked_ids}
      end
    end
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
      |> Enum.map(&as_list_vector/1)

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
      vector = as_list_vector(vector)

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

  defp as_list_vector(vector) when is_list(vector), do: vector
  defp as_list_vector(%Pgvector{} = vector), do: Pgvector.to_list(vector)
end
