defmodule VideoSuggestion.Tags do
  @moduledoc false

  import Ecto.Query, warn: false

  alias VideoSuggestion.EmbeddingWorkerClient
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Reco.Tagging
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Tags.VideoTagSuggestion
  alias VideoSuggestion.Videos.VideoEmbedding

  def ingest_tags(tag_names, opts \\ []) when is_list(tag_names) do
    dims = Keyword.fetch!(opts, :dims)
    embedding_client = Keyword.get(opts, :embedding_client, EmbeddingWorkerClient)
    force = Keyword.get(opts, :force, false)

    tag_names
    |> Enum.map(&normalize_tag_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.uniq()
    |> Enum.each(fn name ->
      tag = Repo.get_by(Tag, name: name)

      cond do
        is_nil(tag) ->
          embed_and_upsert_tag(name, dims, embedding_client)

        not force and embedded_with_dims?(tag, dims) ->
          :ok

        true ->
          embed_and_upsert_tag(name, dims, embedding_client)
      end
    end)

    :ok
  end

  def refresh_video_tag_suggestions(opts \\ []) do
    top_k = Keyword.get(opts, :top_k, 10)
    batch_size = Keyword.get(opts, :batch_size, 50)
    limit = Keyword.get(opts, :limit)
    video_version_prefix = Keyword.get(opts, :video_version_prefix, "qwen3_vl")
    tag_version_prefix = Keyword.get(opts, :tag_version_prefix, "qwen3_vl")

    tags =
      from(t in Tag,
        where: not is_nil(t.vector),
        where: like(t.version, ^"#{tag_version_prefix}%"),
        select: %{id: t.id, name: t.name, vector: t.vector, version: t.version}
      )
      |> Repo.all()

    tags_by_dim = Enum.group_by(tags, &length(&1.vector))

    {updated_videos, skipped_videos} =
      do_refresh_video_tag_suggestions(
        tags_by_dim,
        top_k,
        batch_size,
        limit,
        video_version_prefix,
        0,
        0,
        0
      )

    {:ok, %{updated_videos: updated_videos, skipped_videos: skipped_videos}}
  end

  def likely_tags(video_id, opts \\ []) when is_integer(video_id) do
    limit = Keyword.get(opts, :limit, 20)

    case Repo.get_by(VideoEmbedding, video_id: video_id) do
      nil ->
        {:error, :embedding_missing}

      %VideoEmbedding{version: video_version} ->
        items =
          from(s in VideoTagSuggestion,
            join: t in Tag,
            on: t.id == s.tag_id,
            where: s.video_id == ^video_id and s.video_embedding_version == ^video_version,
            order_by: [desc: s.score, asc: t.name],
            limit: ^limit,
            select: %{tag: t.name, score: s.score}
          )
          |> Repo.all()

        {:ok, items}
    end
  end

  defp do_refresh_video_tag_suggestions(
         tags_by_dim,
         top_k,
         batch_size,
         limit,
         video_version_prefix,
         after_video_id,
         updated_videos,
         skipped_videos
       ) do
    cond do
      is_integer(limit) and updated_videos >= limit ->
        {updated_videos, skipped_videos}

      true ->
        rows = fetch_video_embedding_batch(after_video_id, batch_size, video_version_prefix)

        case rows do
          [] ->
            {updated_videos, skipped_videos}

          _ ->
            {updated_videos, skipped_videos} =
              Enum.reduce(rows, {updated_videos, skipped_videos}, fn {video_id, version, vector},
                                                                     {updated_videos,
                                                                      skipped_videos} ->
                cond do
                  is_integer(limit) and updated_videos >= limit ->
                    {updated_videos, skipped_videos}

                  true ->
                    tags = Map.get(tags_by_dim, length(vector), [])

                    if tags == [] do
                      {updated_videos, skipped_videos + 1}
                    else
                      case Tagging.top_k(vector, tags, top_k) do
                        {:ok, scored} ->
                          persist_video_suggestions(video_id, version, scored)
                          {updated_videos + 1, skipped_videos}

                        {:error, _} ->
                          {updated_videos, skipped_videos + 1}
                      end
                    end
                end
              end)

            last_id = rows |> List.last() |> elem(0)

            do_refresh_video_tag_suggestions(
              tags_by_dim,
              top_k,
              batch_size,
              limit,
              video_version_prefix,
              last_id,
              updated_videos,
              skipped_videos
            )
        end
    end
  end

  defp fetch_video_embedding_batch(after_video_id, batch_size, version_prefix) do
    from(e in VideoEmbedding,
      where: e.video_id > ^after_video_id,
      where: like(e.version, ^"#{version_prefix}%"),
      order_by: [asc: e.video_id],
      limit: ^batch_size,
      select: {e.video_id, e.version, e.vector}
    )
    |> Repo.all()
  end

  defp persist_video_suggestions(video_id, video_version, scored) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Repo.delete_all(
        from(s in VideoTagSuggestion,
          where: s.video_id == ^video_id and s.video_embedding_version == ^video_version
        )
      )

      rows =
        Enum.map(scored, fn {tag, score} ->
          %{
            video_id: video_id,
            tag_id: tag.id,
            score: score,
            video_embedding_version: video_version,
            tag_embedding_version: tag.version,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(VideoTagSuggestion, rows)
    end)

    :ok
  end

  defp embed_and_upsert_tag(name, dims, embedding_client) do
    case embedding_client.embed_text(name, %{dims: dims}) do
      {:ok, %{"version" => version, "embedding" => vector}}
      when is_binary(version) and is_list(vector) ->
        %Tag{}
        |> Tag.changeset(%{name: name, version: version, vector: vector})
        |> Repo.insert(
          conflict_target: :name,
          on_conflict: {:replace, [:version, :vector, :updated_at]}
        )

        :ok

      {:ok, _unexpected} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp embedded_with_dims?(%Tag{vector: vector, version: version}, dims) do
    is_binary(version) and is_list(vector) and length(vector) == dims
  end

  defp normalize_tag_name(raw) do
    raw
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
