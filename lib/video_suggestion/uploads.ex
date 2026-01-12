defmodule VideoSuggestion.Uploads do
  @moduledoc false

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
