defmodule Mix.Tasks.Videos.Import do
  use Mix.Task

  @shortdoc "Import videos from a local folder"

  @moduledoc """
  Imports video files from a local folder into the app.

      mix videos.import PATH [--user-id ID]

  Notes:

  - Detects duplicates by SHA-256 content hash and skips them.
  - Stores videos under `priv/static/uploads/`.
  """

  @requirements ["app.start"]

  @switches [user_id: :integer]

  @video_exts ~w(.mp4 .m4v .mov .webm)

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

    dir =
      case argv do
        [dir] -> dir
        _ -> Mix.raise("Usage: mix videos.import PATH [--user-id ID]")
      end

    dir = Path.expand(dir)

    if not File.dir?(dir) do
      Mix.raise("Folder does not exist: #{dir}")
    end

    uploader_id = Keyword.get(opts, :user_id) || default_uploader_id()

    if is_nil(uploader_id) do
      Mix.raise("No users found. Create an admin user first, or pass --user-id.")
    end

    files = video_files(dir)

    if files == [] do
      Mix.shell().info("No video files found in #{dir}.")
    else
      Mix.shell().info("Importing #{length(files)} video(s) from #{dir}…")

      Uploads.ensure_dir!()

      {created, duplicates, failures, _seen} =
        Enum.reduce(files, {0, 0, 0, MapSet.new()}, fn path,
                                                       {created, duplicates, failures,
                                                        seen_hashes} ->
          ext = Path.extname(path) |> String.downcase()

          hash =
            try do
              Uploads.sha256_file(path)
            rescue
              _ -> nil
            end

          cond do
            is_nil(hash) ->
              Mix.shell().error("Failed to read #{path}")
              {created, duplicates, failures + 1, seen_hashes}

            MapSet.member?(seen_hashes, hash) ->
              {created, duplicates + 1, failures, seen_hashes}

            Videos.content_hash_exists?(hash) ->
              {created, duplicates + 1, failures, seen_hashes}

            true ->
              seen_hashes = MapSet.put(seen_hashes, hash)
              storage_key = Ecto.UUID.generate() <> ext
              dest = Uploads.path(storage_key)

              case File.cp(path, dest) do
                :ok ->
                  caption = Path.basename(path) |> Path.rootname()

                  attrs = %{
                    user_id: uploader_id,
                    caption: caption,
                    storage_key: storage_key,
                    original_filename: Path.basename(path),
                    content_type: content_type_for_ext(ext),
                    content_hash: hash
                  }

                  case Videos.create_video(attrs) do
                    {:ok, _video} ->
                      {created + 1, duplicates, failures, seen_hashes}

                    {:error, %Ecto.Changeset{} = changeset} ->
                      File.rm_rf(dest)

                      if changeset.errors[:content_hash] do
                        {created, duplicates + 1, failures, seen_hashes}
                      else
                        Mix.shell().error(
                          "Failed to import #{path}: #{inspect(changeset.errors)}"
                        )

                        {created, duplicates, failures + 1, seen_hashes}
                      end
                  end

                {:error, reason} ->
                  Mix.shell().error("Failed to copy #{path}: #{inspect(reason)}")
                  {created, duplicates, failures + 1, seen_hashes}
              end
          end
        end)

      Mix.shell().info(
        "Done. Imported: #{created}, skipped duplicates: #{duplicates}, failures: #{failures}."
      )
    end
  end

  defp video_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.filter(fn path -> String.downcase(Path.extname(path)) in @video_exts end)
    |> Enum.sort()
  end

  defp default_uploader_id do
    Repo.one(from u in User, where: u.is_admin == true, order_by: [asc: u.id], select: u.id) ||
      Repo.one(from u in User, order_by: [asc: u.id], select: u.id)
  end

  defp content_type_for_ext(".mp4"), do: "video/mp4"
  defp content_type_for_ext(".m4v"), do: "video/mp4"
  defp content_type_for_ext(".mov"), do: "video/quicktime"
  defp content_type_for_ext(".webm"), do: "video/webm"
  defp content_type_for_ext(_), do: "application/octet-stream"
end
