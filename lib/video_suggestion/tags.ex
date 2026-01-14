defmodule VideoSuggestion.Tags do
  @moduledoc false

  import Ecto.Query, warn: false

  alias VideoSuggestion.EmbeddingWorkerClient
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Tags.VideoTagSuggestion
  alias VideoSuggestion.Videos.Video
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

    {updated_videos, skipped_videos} =
      do_refresh_video_tag_suggestions(
        top_k,
        batch_size,
        limit,
        video_version_prefix,
        tag_version_prefix,
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
            select: %{id: t.id, tag: t.name, score: s.score}
          )
          |> Repo.all()

        {:ok, items}
    end
  end

  def list_tags_by_frequency(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(s in VideoTagSuggestion,
      join: t in Tag,
      on: t.id == s.tag_id,
      join: e in VideoEmbedding,
      on: e.video_id == s.video_id,
      where: s.video_embedding_version == e.version,
      where: s.tag_embedding_version == t.version,
      group_by: [t.id, t.name],
      order_by: [desc: count(s.video_id, :distinct), asc: t.name],
      limit: ^limit,
      select: %{id: t.id, tag: t.name, count: count(s.video_id, :distinct)}
    )
    |> Repo.all()
  end

  def list_videos_for_tag(tag_id, opts \\ []) when is_integer(tag_id) do
    limit = Keyword.get(opts, :limit, 100)

    from(s in VideoTagSuggestion,
      join: v in Video,
      on: v.id == s.video_id,
      join: e in VideoEmbedding,
      on: e.video_id == v.id,
      join: t in Tag,
      on: t.id == s.tag_id,
      where: s.tag_id == ^tag_id,
      where: s.video_embedding_version == e.version,
      where: s.tag_embedding_version == t.version,
      order_by: [desc: s.score, desc: v.inserted_at, desc: v.id],
      limit: ^limit,
      select: %{video: v, score: s.score}
    )
    |> Repo.all()
  end

  defp do_refresh_video_tag_suggestions(
         top_k,
         batch_size,
         limit,
         video_version_prefix,
         tag_version_prefix,
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
                    tags = top_tags_for_video(vector, tag_version_prefix, top_k)

                    if tags == [] do
                      {updated_videos, skipped_videos + 1}
                    else
                      persist_video_suggestions(video_id, version, tags)
                      {updated_videos + 1, skipped_videos}
                    end
                end
              end)

            last_id = rows |> List.last() |> elem(0)

            do_refresh_video_tag_suggestions(
              top_k,
              batch_size,
              limit,
              video_version_prefix,
              tag_version_prefix,
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
        Enum.map(scored, fn %{tag_id: tag_id, tag_version: tag_version, score: score} ->
          %{
            video_id: video_id,
            tag_id: tag_id,
            score: score,
            video_embedding_version: video_version,
            tag_embedding_version: tag_version,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(VideoTagSuggestion, rows)
    end)

    :ok
  end

  defp top_tags_for_video(video_vector, tag_version_prefix, top_k) do
    from(t in Tag,
      where: not is_nil(t.vector),
      where: like(t.version, ^"#{tag_version_prefix}%"),
      order_by: fragment("? <=> ?", t.vector, ^video_vector),
      limit: ^top_k,
      select: %{
        tag_id: t.id,
        tag_version: t.version,
        score: fragment("1 - (? <=> ?)", t.vector, ^video_vector)
      }
    )
    |> Repo.all()
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
    is_binary(version) and vector_dims(vector) == dims
  end

  defp vector_dims(nil), do: 0

  defp vector_dims(vector) when is_list(vector), do: length(vector)

  defp vector_dims(%Pgvector{data: <<dim::unsigned-16, _::unsigned-16, _::binary>>}), do: dim

  defp normalize_tag_name(raw) do
    raw
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
