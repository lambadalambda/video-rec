defmodule VideoSuggestion.Uploads do
  @moduledoc false

  def sha256_file(path) when is_binary(path) do
    path
    |> File.stream!([], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, ctx ->
      :crypto.hash_update(ctx, chunk)
    end)
    |> :crypto.hash_final()
  end

  def dir do
    Application.app_dir(:video_suggestion, "priv/static/uploads")
  end

  def ensure_dir! do
    File.mkdir_p!(dir())
  end

  def path(storage_key) when is_binary(storage_key) do
    Path.join(dir(), storage_key)
  end

  def url(storage_key) when is_binary(storage_key) do
    "/uploads/" <> storage_key
  end
end
