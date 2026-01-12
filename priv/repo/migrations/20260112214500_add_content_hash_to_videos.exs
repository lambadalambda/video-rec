defmodule VideoSuggestion.Repo.Migrations.AddContentHashToVideos do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      add :content_hash, :binary
    end

    flush()

    backfill_content_hashes()

    alter table(:videos) do
      modify :content_hash, :binary, null: false
    end

    create unique_index(:videos, [:content_hash])
  end

  def down do
    drop index(:videos, [:content_hash])

    alter table(:videos) do
      remove :content_hash
    end
  end

  defp backfill_content_hashes do
    %{rows: rows} =
      repo().query!(
        "SELECT id, storage_key FROM videos WHERE content_hash IS NULL ORDER BY id",
        []
      )

    uploads_dir = uploads_dir()

    Enum.reduce(rows, MapSet.new(), fn [id, storage_key], seen ->
      hash =
        uploads_dir
        |> Path.join(storage_key)
        |> sha256_file()

      {hash, seen} =
        if MapSet.member?(seen, hash) do
          {:crypto.hash(:sha256, "dup:" <> storage_key), seen}
        else
          {hash, MapSet.put(seen, hash)}
        end

      repo().query!("UPDATE videos SET content_hash = $1 WHERE id = $2", [hash, id])
      seen
    end)
  end

  defp sha256_file(path) do
    if File.exists?(path) do
      path
      |> File.stream!([], 2048)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, ctx ->
        :crypto.hash_update(ctx, chunk)
      end)
      |> :crypto.hash_final()
    else
      :crypto.hash(:sha256, Path.basename(path))
    end
  end

  defp uploads_dir do
    :video_suggestion
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("static/uploads")
  end
end
