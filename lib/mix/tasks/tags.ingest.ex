defmodule Mix.Tasks.Tags.Ingest do
  use Mix.Task

  @shortdoc "Ingest tags and compute likely tags for all videos"

  @moduledoc """
  Ingests tags from a text file (one tag per line), embeds them, and stores
  the top-K most similar tags for each video.

      mix tags.ingest TAGS_FILE [--force] [--top-k N] [--batch-size N] [--limit N]
        [--dims N] [--video-version-prefix PREFIX] [--tag-version-prefix PREFIX]

  Notes:

  - Requires the embedding worker to be running (uses `/v1/embed/text`).
  - Uses video embeddings matching `--video-version-prefix` (default: `qwen3_vl`).
  - Stores per-video suggestions in `video_tag_suggestions`.
  """

  @requirements ["app.start"]

  @switches [
    force: :boolean,
    top_k: :integer,
    batch_size: :integer,
    limit: :integer,
    dims: :integer,
    video_version_prefix: :string,
    tag_version_prefix: :string
  ]

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Tags
  alias VideoSuggestion.Videos.VideoEmbedding

  import Ecto.Query, warn: false

  @impl true
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, switches: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    path =
      case argv do
        [path] -> path
        _ -> Mix.raise("Usage: mix tags.ingest TAGS_FILE [--top-k N] ...")
      end

    force = Keyword.get(opts, :force, false)
    top_k = Keyword.get(opts, :top_k, 10)
    batch_size = Keyword.get(opts, :batch_size, 50)
    limit = Keyword.get(opts, :limit)
    video_version_prefix = Keyword.get(opts, :video_version_prefix, "qwen3_vl")
    tag_version_prefix = Keyword.get(opts, :tag_version_prefix, "qwen3_vl")

    dims =
      cond do
        is_integer(opts[:dims]) and opts[:dims] > 0 ->
          opts[:dims]

        is_integer(Application.get_env(:video_suggestion, :embedding_dims)) and
            Application.get_env(:video_suggestion, :embedding_dims) > 0 ->
          Application.get_env(:video_suggestion, :embedding_dims)

        true ->
          infer_dims!(video_version_prefix)
      end

    tags =
      path
      |> File.stream!()
      |> Enum.map(&String.trim/1)

    :ok = Tags.ingest_tags(tags, dims: dims, force: force)

    {:ok, %{updated_videos: updated_videos, skipped_videos: skipped_videos}} =
      Tags.refresh_video_tag_suggestions(
        top_k: top_k,
        batch_size: batch_size,
        limit: limit,
        video_version_prefix: video_version_prefix,
        tag_version_prefix: tag_version_prefix
      )

    Mix.shell().info("Done. Updated videos: #{updated_videos}, skipped: #{skipped_videos}.")
  end

  defp infer_dims!(video_version_prefix) do
    dims =
      from(e in VideoEmbedding,
        where: like(e.version, ^"#{video_version_prefix}%"),
        limit: 1,
        select: fragment("vector_dims(?)", e.vector)
      )
      |> Repo.one()

    if is_integer(dims) and dims > 0 do
      dims
    else
      Mix.raise("Could not infer dims from video embeddings. Pass --dims.")
    end
  end
end
