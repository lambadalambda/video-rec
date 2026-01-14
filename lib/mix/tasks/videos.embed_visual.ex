defmodule Mix.Tasks.Videos.EmbedVisual do
  use Mix.Task

  @shortdoc "Compute visual embeddings for all videos"

  @moduledoc """
  Computes embeddings for videos and stores them in Postgres.

      mix videos.embed_visual [--force] [--batch-size N] [--limit N] [--dims N]

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
    dims: :integer
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

    Uploads.ensure_dir!()

    {updated, skipped, failures} = embed_all(force, batch_size, limit, dims)

    Mix.shell().info("Done. Updated: #{updated}, skipped: #{skipped}, failures: #{failures}.")
  end

  defp embed_all(force, batch_size, limit, dims) do
    do_embed_all(force, batch_size, limit, dims, 0, 0, 0, 0)
  end

  defp do_embed_all(force, batch_size, limit, dims, after_id, updated, skipped, failures) do
    cond do
      is_integer(limit) and updated >= limit ->
        {updated, skipped, failures}

      true ->
        rows = fetch_batch(after_id, batch_size)

        case rows do
          [] ->
            {updated, skipped, failures}

          _ ->
            {updated, skipped, failures} =
              Enum.reduce(rows, {updated, skipped, failures}, fn {video, embedding},
                                                                 {updated, skipped, failures} ->
                cond do
                  is_integer(limit) and updated >= limit ->
                    {updated, skipped, failures}

                  not File.exists?(Uploads.path(video.storage_key)) ->
                    {updated, skipped, failures + 1}

                  not force and skip_embedding?(embedding) ->
                    {updated, skipped + 1, failures}

                  true ->
                    attrs =
                      %{
                        caption: video.caption || "",
                        transcribe: false
                      }
                      |> maybe_put_dims(dims)

                    embed_response =
                      case System.get_env("EMBEDDING_WORKER_MEDIA_MODE") do
                        "upload" ->
                          path = Uploads.path(video.storage_key)

                          with {:ok, frames} <- Media.extract_video_frames(path) do
                            EmbeddingWorkerClient.embed_video_frames(frames, attrs)
                          end

                        _ ->
                          EmbeddingWorkerClient.embed_video(video.storage_key, attrs)
                      end

                    case embed_response do
                      {:ok, %{"version" => version, "embedding" => vector}} ->
                        case Videos.upsert_video_embedding(video.id, version, vector) do
                          {:ok, _} -> {updated + 1, skipped, failures}
                          {:error, _} -> {updated, skipped, failures + 1}
                        end

                      {:ok, _unexpected} ->
                        {updated, skipped, failures + 1}

                      {:error, _reason} ->
                        {updated, skipped, failures + 1}
                    end
                end
              end)

            last_id = rows |> List.last() |> elem(0) |> Map.fetch!(:id)
            do_embed_all(force, batch_size, limit, dims, last_id, updated, skipped, failures)
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
