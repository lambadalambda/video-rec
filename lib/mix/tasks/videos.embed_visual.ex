defmodule Mix.Tasks.Videos.EmbedVisual do
  use Mix.Task

  @shortdoc "Compute visual embeddings for all videos"

  @moduledoc """
  Computes embeddings for videos and stores them in Postgres.

      mix videos.embed_visual [--force] [--batch-size N] [--limit N] [--dims N] [--concurrency N]

  Notes:

  - Requires the embedding worker to be running.
  - Sends `transcribe: false` to avoid audio transcription.
  - Skips videos already embedded with `qwen3_vl_v1` unless `--force` is given.
  """

  @requirements ["app.start"]

  @switches [
    force: :boolean,
    batch_size: :integer,
    limit: :integer,
    dims: :integer,
    concurrency: :integer
  ]

  alias VideoSuggestion.EmbeddingWorkerClient
  alias VideoSuggestion.Media
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Videos.VideoEmbedding

  import Ecto.Query, warn: false

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, switches: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    force = Keyword.get(opts, :force, false)
    batch_size = Keyword.get(opts, :batch_size, 50)
    limit = Keyword.get(opts, :limit)
    dims = Keyword.get(opts, :dims)
    concurrency = Keyword.get(opts, :concurrency, 4)
    req_opts = Process.get({:video_suggestion, :embedding_worker_req_options}) || []

    Uploads.ensure_dir!()

    {updated, skipped, failures} =
      embed_all(force, batch_size, limit, dims, concurrency, req_opts)

    Mix.shell().info("Done. Updated: #{updated}, skipped: #{skipped}, failures: #{failures}.")
  end

  defp embed_all(force, batch_size, limit, dims, concurrency, req_opts) do
    do_embed_all(force, batch_size, limit, dims, concurrency, req_opts, 0, 0, 0, 0)
  end

  defp do_embed_all(
         force,
         batch_size,
         limit,
         dims,
         concurrency,
         req_opts,
         after_id,
         updated,
         skipped,
         failures
       ) do
    cond do
      is_integer(limit) and updated >= limit ->
        {updated, skipped, failures}

      true ->
        rows = fetch_batch(after_id, batch_size)

        case rows do
          [] ->
            {updated, skipped, failures}

          _ ->
            max_concurrency =
              if is_integer(concurrency) and concurrency > 0, do: concurrency, else: 1

            {updated, skipped, failures} =
              rows
              |> Task.async_stream(
                fn {video, embedding} ->
                  cond do
                    not File.exists?(Uploads.path(video.storage_key)) ->
                      :failed

                    not force and skip_embedding?(embedding) ->
                      :skipped

                    true ->
                      attrs =
                        %{caption: video.caption || "", transcribe: false}
                        |> maybe_put_dims(dims)

                      embed_response =
                        case System.get_env("EMBEDDING_WORKER_MEDIA_MODE") do
                          "upload" ->
                            path = Uploads.path(video.storage_key)

                            with {:ok, frames} <- Media.extract_video_frames(path) do
                              EmbeddingWorkerClient.embed_video_frames(frames, attrs, req_opts)
                            end

                          _ ->
                            EmbeddingWorkerClient.embed_video(video.storage_key, attrs, req_opts)
                        end

                      case embed_response do
                        {:ok, %{"version" => version, "embedding" => vector}} ->
                          case Videos.upsert_video_embedding(video.id, version, vector) do
                            {:ok, _} -> :updated
                            {:error, _} -> :failed
                          end

                        _ ->
                          :failed
                      end
                  end
                end,
                max_concurrency: max_concurrency,
                ordered: false,
                timeout: :infinity
              )
              |> Enum.reduce({updated, skipped, failures}, fn
                {:ok, :updated}, {updated, skipped, failures} ->
                  {updated + 1, skipped, failures}

                {:ok, :skipped}, {updated, skipped, failures} ->
                  {updated, skipped + 1, failures}

                {:ok, :failed}, {updated, skipped, failures} ->
                  {updated, skipped, failures + 1}

                {:exit, _reason}, {updated, skipped, failures} ->
                  {updated, skipped, failures + 1}
              end)

            last_id = rows |> List.last() |> elem(0) |> Map.fetch!(:id)

            do_embed_all(
              force,
              batch_size,
              limit,
              dims,
              concurrency,
              req_opts,
              last_id,
              updated,
              skipped,
              failures
            )
        end
    end
  end

  defp fetch_batch(after_id, batch_size) do
    query =
      from v in Video,
        left_join: e in VideoEmbedding,
        on: e.video_id == v.id,
        where: v.id > ^after_id,
        order_by: [asc: v.id],
        limit: ^batch_size,
        select: {v, e}

    Repo.all(query)
  end

  defp skip_embedding?(%VideoEmbedding{version: "qwen3_vl_v1"}), do: true
  defp skip_embedding?(_), do: false

  defp maybe_put_dims(attrs, dims) when is_integer(dims) and dims > 0,
    do: Map.put(attrs, :dims, dims)

  defp maybe_put_dims(attrs, _), do: attrs
end
