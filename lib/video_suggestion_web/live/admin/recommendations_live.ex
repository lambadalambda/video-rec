defmodule VideoSuggestionWeb.Admin.RecommendationsLive do
  use VideoSuggestionWeb, :live_view

  import Ecto.Query, warn: false

  alias VideoSuggestion.Recommendations
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestionWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    {items, message} = load_recommendations(user_id)

    {:ok, assign(socket, items: items, message: message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Recommendations</.header>

        <%= if @items == [] do %>
          <p class="text-sm opacity-70">{@message}</p>
        <% else %>
          <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
            <div :for={item <- @items} class="p-4">
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="font-semibold truncate">{item.video.caption}</div>
                  <div class="text-xs opacity-70">score: {format_score(item.score)}</div>
                </div>

                <.link navigate={~p"/"} class="btn btn-ghost btn-xs">
                  Open feed
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp load_recommendations(user_id) do
    case Recommendations.rank_videos_for_user(user_id, limit: 25) do
      {:ok, ranked} ->
        ids = Enum.map(ranked, &elem(&1, 0))

        videos =
          from(v in Video, where: v.id in ^ids, select: {v.id, v})
          |> Repo.all()
          |> Map.new()

        items =
          for {id, score} <- ranked,
              video = Map.get(videos, id),
              not is_nil(video) do
            %{video: video, score: score}
          end

        {items, nil}

      {:error, :empty} ->
        {[], "Favorite some videos to get recommendations."}

      {:error, _reason} ->
        {[], "Recommendations are not available yet."}
    end
  end

  defp format_score(score) when is_float(score) do
    :io_lib.format("~.4f", [score]) |> IO.iodata_to_binary()
  end
end
