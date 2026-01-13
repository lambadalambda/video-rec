defmodule Mix.Tasks.Videos.Transcribe do
  use Mix.Task

  @shortdoc "Run Whisper transcription for all videos"

  @moduledoc """
  Runs Whisper transcription for videos and stores transcripts in Postgres.

      mix videos.transcribe [--force] [--batch-size N] [--limit N]

  Notes:

  - Requires the embedding worker to be running with Whisper enabled.
  - Skips videos that already have a transcript unless `--force` is given.
  """

  @requirements ["app.start"]

  @switches [
    force: :boolean,
    batch_size: :integer,
    limit: :integer
  ]

  alias VideoSuggestion.EmbeddingWorkerClient
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Repo

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

    Uploads.ensure_dir!()

    {updated, skipped, failures} = transcribe_all(force, batch_size, limit)

    Mix.shell().info("Done. Updated: #{updated}, skipped: #{skipped}, failures: #{failures}.")
  end

  defp transcribe_all(force, batch_size, limit) do
    do_transcribe_all(force, batch_size, limit, 0, 0, 0, 0)
  end

  defp do_transcribe_all(force, batch_size, limit, after_id, updated, skipped, failures) do
    cond do
      is_integer(limit) and updated >= limit ->
        {updated, skipped, failures}

      true ->
        videos = fetch_batch(after_id, batch_size, force)

        case videos do
          [] ->
            {updated, skipped, failures}

          _ ->
            {updated, skipped, failures} =
              Enum.reduce(videos, {updated, skipped, failures}, fn video,
                                                                   {updated, skipped, failures} ->
                cond do
                  is_integer(limit) and updated >= limit ->
                    {updated, skipped, failures}

                  not File.exists?(Uploads.path(video.storage_key)) ->
                    {updated, skipped, failures + 1}

                  true ->
                    case EmbeddingWorkerClient.transcribe_video(video.storage_key) do
                      {:ok, %{"transcript" => transcript}} ->
                        transcript = (transcript || "") |> String.trim()

                        if transcript == "" do
                          {updated, skipped + 1, failures}
                        else
                          case Videos.set_video_transcript(video.id, transcript) do
                            {:ok, _} -> {updated + 1, skipped, failures}
                            {:error, _} -> {updated, skipped, failures + 1}
                          end
                        end

                      {:ok, _unexpected} ->
                        {updated, skipped, failures + 1}

                      {:error, _reason} ->
                        {updated, skipped, failures + 1}
                    end
                end
              end)

            last_id = List.last(videos).id
            do_transcribe_all(force, batch_size, limit, last_id, updated, skipped, failures)
        end
    end
  end

  defp fetch_batch(after_id, batch_size, force) do
    query =
      from v in Video,
        where: v.id > ^after_id,
        order_by: [asc: v.id],
        limit: ^batch_size

    query =
      if force do
        query
      else
        from v in query,
          where: is_nil(v.transcript) or v.transcript == ""
      end

    Repo.all(query)
  end
end
