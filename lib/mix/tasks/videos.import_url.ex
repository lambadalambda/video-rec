defmodule Mix.Tasks.Videos.ImportUrl do
  use Mix.Task

  @shortdoc "Import videos by scraping a URL (e.g. 4chan threads)"

  @moduledoc """
  Downloads linked `.webm` / `.mp4` files from a URL, converts them to `.mp4`,
  and imports them into the app.

      mix videos.import_url URL [--user-id ID] [--limit N]

  Notes:

  - Detects duplicates by SHA-256 content hash and skips them.
  - Stores videos under `priv/static/uploads/`.
  - For 4chan thread URLs, prefers the official JSON API.
  """

  @requirements ["app.start"]

  @switches [
    user_id: :integer,
    limit: :integer
  ]

  @video_exts ~w(.mp4 .webm)

  @req_options_process_key {:video_suggestion, :videos_import_req_options}

  @default_req_options [
    redirect: true,
    receive_timeout: :timer.minutes(10),
    headers: [
      {"user-agent", "video-suggestion/0.1 (videos.import_url)"}
    ]
  ]

  alias VideoSuggestion.Accounts.User
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  import Ecto.Query, warn: false

  @impl true
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, switches: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    url =
      case argv do
        [url] -> url
        _ -> Mix.raise("Usage: mix videos.import_url URL [--user-id ID] [--limit N]")
      end

    uploader_id = Keyword.get(opts, :user_id) || default_uploader_id()

    if is_nil(uploader_id) do
      Mix.raise("No users found. Create an admin user first, or pass --user-id.")
    end

    limit = Keyword.get(opts, :limit)

    Uploads.ensure_dir!()

    entries = fetch_video_entries(url)
    entries = maybe_limit(entries, limit)

    if entries == [] do
      Mix.shell().info("No videos found at #{url}.")
      :ok
    else
      Mix.shell().info("Importing #{length(entries)} video(s) from #{url}…")

      {created, duplicates, failures, _seen} =
        Enum.reduce(entries, {0, 0, 0, MapSet.new()}, fn entry,
                                                         {created, duplicates, failures,
                                                          seen_hashes} ->
          case download_and_import_entry(entry, uploader_id, seen_hashes) do
            {:ok, :created, seen_hashes} -> {created + 1, duplicates, failures, seen_hashes}
            {:ok, :duplicate, seen_hashes} -> {created, duplicates + 1, failures, seen_hashes}
            {:error, _reason, seen_hashes} -> {created, duplicates, failures + 1, seen_hashes}
          end
        end)

      Mix.shell().info(
        "Done. Imported: #{created}, skipped duplicates: #{duplicates}, failures: #{failures}."
      )
    end
  end

  defp download_and_import_entry(entry, uploader_id, seen_hashes) do
    url = entry.url
    ext = Path.extname(entry.original_filename || url) |> String.downcase()

    if ext not in @video_exts do
      {:error, :unsupported_ext, seen_hashes}
    else
      tmp_dir = tmp_dir!()
      downloaded_path = Path.join(tmp_dir, Ecto.UUID.generate() <> ext)

      try do
        with :ok <- download_file(url, downloaded_path),
             {:ok, hash} <- sha256_file(downloaded_path) do
          cond do
            MapSet.member?(seen_hashes, hash) ->
              {:ok, :duplicate, seen_hashes}

            Videos.content_hash_exists?(hash) ->
              {:ok, :duplicate, seen_hashes}

            true ->
              seen_hashes = MapSet.put(seen_hashes, hash)

              with {:ok, mp4_path} <- ensure_mp4(downloaded_path, ext),
                   {:ok, storage_key} <- store_mp4(mp4_path),
                   {:ok, _video} <- create_video(entry, uploader_id, storage_key, hash) do
                {:ok, :created, seen_hashes}
              else
                {:error, :duplicate} ->
                  {:ok, :duplicate, seen_hashes}

                {:error, reason} ->
                  Mix.shell().error("Failed to import #{url}: #{inspect(reason)}")
                  {:error, reason, seen_hashes}
              end
          end
        else
          {:error, reason} ->
            Mix.shell().error("Failed to download #{url}: #{inspect(reason)}")
            {:error, reason, seen_hashes}
        end
      after
        File.rm_rf(tmp_dir)
      end
    end
  end

  defp sha256_file(path) do
    try do
      {:ok, Uploads.sha256_file(path)}
    rescue
      _ -> {:error, :hash_failed}
    end
  end

  defp store_mp4(mp4_path) do
    storage_key = Ecto.UUID.generate() <> ".mp4"
    dest = Uploads.path(storage_key)

    case File.cp(mp4_path, dest) do
      :ok ->
        {:ok, storage_key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_video(entry, uploader_id, storage_key, hash) do
    caption =
      entry.caption
      |> to_string()
      |> String.trim()

    caption =
      if caption == "" do
        Path.basename(entry.original_filename || entry.url) |> Path.rootname()
      else
        caption
      end

    attrs = %{
      user_id: uploader_id,
      caption: caption,
      storage_key: storage_key,
      original_filename: Path.basename(entry.original_filename || caption <> ".mp4"),
      content_type: "video/mp4",
      content_hash: hash
    }

    case Videos.create_video(attrs) do
      {:ok, video} ->
        {:ok, video}

      {:error, %Ecto.Changeset{} = changeset} ->
        File.rm_rf(Uploads.path(storage_key))

        if changeset.errors[:content_hash] do
          {:error, :duplicate}
        else
          {:error, changeset.errors}
        end
    end
  end

  defp ensure_mp4(downloaded_path, ".mp4"), do: {:ok, downloaded_path}

  defp ensure_mp4(downloaded_path, _ext) do
    ffmpeg = ffmpeg_bin!()
    out_path = Path.rootname(downloaded_path) <> ".mp4"

    args = [
      "-y",
      "-i",
      downloaded_path,
      "-map_metadata",
      "-1",
      "-map",
      "0:v:0",
      "-map",
      "0:a?",
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "23",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      "128k",
      "-movflags",
      "+faststart",
      out_path
    ]

    {_out, status} = System.cmd(ffmpeg, args, stderr_to_stdout: true)

    if status == 0 and File.exists?(out_path) do
      {:ok, out_path}
    else
      {:error, :ffmpeg_failed}
    end
  end

  defp ffmpeg_bin! do
    System.get_env("FFMPEG_BIN") || System.find_executable("ffmpeg") ||
      Mix.raise("ffmpeg not found")
  end

  defp download_file(url, dest) do
    opts = req_options()

    resp =
      Req.get!(
        url,
        Keyword.merge(opts,
          into: File.stream!(dest)
        )
      )

    case resp do
      %{status: status} when status in 200..299 ->
        :ok

      %{status: status, body: body} ->
        File.rm_rf(dest)
        {:error, {:http_error, status, body}}
    end
  end

  defp fetch_video_entries(url) do
    case parse_4chan_thread_url(url) do
      {:ok, %{board: board, thread_id: thread_id}} ->
        fetch_4chan_entries(board, thread_id)

      :error ->
        fetch_generic_entries(url)
    end
  end

  defp fetch_4chan_entries(board, thread_id) when is_binary(board) and is_binary(thread_id) do
    api_url = "https://a.4cdn.org/#{board}/thread/#{thread_id}.json"
    opts = req_options()

    case Req.get!(api_url, opts) do
      %{status: status, body: body} when status in 200..299 ->
        payload = decode_json_body(body)
        posts = payload["posts"] || []

        posts
        |> Enum.flat_map(fn post ->
          with tim when not is_nil(tim) <- post["tim"],
               ext when ext in @video_exts <- post["ext"] do
            filename = post["filename"] || to_string(tim)
            file_url = "https://i.4cdn.org/#{board}/#{tim}#{ext}"

            [
              %{
                url: file_url,
                original_filename: "#{filename}#{ext}",
                caption: filename
              }
            ]
          else
            _ -> []
          end
        end)
        |> dedupe_entries()

      _ ->
        []
    end
  end

  defp fetch_generic_entries(url) do
    opts = req_options()

    case Req.get!(url, opts) do
      %{status: status, body: body} when status in 200..299 ->
        body = to_string(body)

        regex = ~r/(https?:\/\/|\/\/)[^"'\\s<>]+\\.(?:webm|mp4)/i

        Regex.scan(regex, body)
        |> Enum.map(&List.first/1)
        |> Enum.map(&normalize_url/1)
        |> Enum.map(fn file_url ->
          %{
            url: file_url,
            original_filename: Path.basename(file_url),
            caption: Path.basename(file_url) |> Path.rootname()
          }
        end)
        |> dedupe_entries()

      _ ->
        []
    end
  end

  defp decode_json_body(body) when is_map(body), do: body

  defp decode_json_body(body) do
    body
    |> IO.iodata_to_binary()
    |> Jason.decode!()
  end

  defp normalize_url("//" <> rest), do: "https://" <> rest
  defp normalize_url(url), do: url

  defp dedupe_entries(entries) do
    {entries, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, seen} ->
        if MapSet.member?(seen, entry.url) do
          {acc, seen}
        else
          {[entry | acc], MapSet.put(seen, entry.url)}
        end
      end)

    Enum.reverse(entries)
  end

  defp parse_4chan_thread_url(url) when is_binary(url) do
    %URI{host: host, path: path} = URI.parse(url)

    if host in ["boards.4chan.org", "boards.4channel.org"] and is_binary(path) do
      parts = path |> String.trim("/") |> String.split("/", trim: true)

      case parts do
        [board, "thread", thread_id | _rest] when board != "" and thread_id != "" ->
          {:ok, %{board: board, thread_id: thread_id}}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp maybe_limit(entries, limit) when is_integer(limit) and limit > 0 do
    Enum.take(entries, limit)
  end

  defp maybe_limit(entries, _), do: entries

  defp tmp_dir! do
    dir =
      System.tmp_dir!()
      |> Path.join("video_suggestion_import_url_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp default_uploader_id do
    Repo.one(from u in User, where: u.is_admin == true, order_by: [asc: u.id], select: u.id) ||
      Repo.one(from u in User, order_by: [asc: u.id], select: u.id)
  end

  defp req_options do
    @default_req_options
    |> Keyword.merge(Application.get_env(:video_suggestion, :videos_import_req_options, []))
    |> Keyword.merge(Process.get(@req_options_process_key) || [])
  end
end
