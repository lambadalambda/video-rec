defmodule VideoSuggestion.Videos do
  @moduledoc """
  The Videos context.
  """

  import Ecto.Query, warn: false

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos.Video

  def list_videos(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Video
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_video!(id), do: Repo.get!(Video, id)

  def create_video(attrs) do
    %Video{}
    |> Video.changeset(attrs)
    |> Repo.insert()
  end
end
