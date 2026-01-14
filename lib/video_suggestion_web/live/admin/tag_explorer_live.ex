defmodule VideoSuggestionWeb.Admin.TagExplorerLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Tags
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Uploads
  alias VideoSuggestionWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:tags, [])
     |> assign(:tag, nil)
     |> assign(:items, [])
     |> assign(:message, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        tags = Tags.list_tags_by_frequency()

        {:noreply,
         socket
         |> assign(:tags, tags)
         |> assign(:tag, nil)
         |> assign(:items, [])
         |> assign(:message, nil)}

      :show ->
        case parse_id(params["id"]) do
          {:ok, id} ->
            tag = Repo.get(Tag, id)

            if is_nil(tag) do
              {:noreply, push_navigate(socket, to: ~p"/admin/tags")}
            else
              items = Tags.list_videos_for_tag(tag.id, limit: 100)
              message = if items == [], do: "No videos match this tag yet.", else: nil

              {:noreply,
               socket
               |> assign(:tag, tag)
               |> assign(:items, items)
               |> assign(:message, message)}
            end

          :error ->
            {:noreply, push_navigate(socket, to: ~p"/admin/tags")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Tags</.header>

        <%= case @live_action do %>
          <% :index -> %>
            <p class="text-sm opacity-70">
              Tags are ranked by how often they appear in the precomputed top-K suggestions.
            </p>

            <%= if @tags == [] do %>
              <p class="text-sm opacity-70">No tags yet. Run mix tags.ingest.</p>
            <% else %>
              <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
                <div :for={row <- @tags} class="p-4">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="font-semibold truncate">{row.tag}</div>
                      <div class="text-xs opacity-70">videos: {row.count}</div>
                    </div>

                    <.link navigate={~p"/admin/tags/#{row.id}"} class="btn btn-ghost btn-xs">
                      Similar
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          <% :show -> %>
            <div class="flex items-center justify-between gap-4">
              <div class="min-w-0">
                <div class="font-semibold truncate">{@tag.name}</div>
                <div class="text-xs opacity-70">Top matches</div>
              </div>

              <.link navigate={~p"/admin/tags"} class="btn btn-ghost btn-sm">
                Back
              </.link>
            </div>

            <%= if @items == [] do %>
              <p class="text-sm opacity-70">{@message}</p>
            <% else %>
              <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
                <div :for={item <- @items} class="p-4 space-y-3">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="font-semibold truncate">{video_label(item.video)}</div>
                      <div class="text-xs opacity-70">score: {format_score(item.score)}</div>
                    </div>

                    <.link
                      navigate={~p"/admin/similarity/#{item.video.id}"}
                      class="btn btn-ghost btn-xs"
                    >
                      Similar
                    </.link>
                  </div>

                  <div class="rounded-box border border-base-300 bg-base-200 overflow-hidden">
                    <video
                      class="w-full aspect-video bg-black"
                      src={Uploads.url(item.video.storage_key)}
                      playsinline
                      muted
                      loop
                      preload="metadata"
                    >
                    </video>
                  </div>
                </div>
              </div>
            <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp parse_id(nil), do: :error

  defp parse_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp video_label(video) do
    case String.trim(video.caption || "") do
      "" -> video.storage_key
      caption -> caption
    end
  end

  defp format_score(score) when is_float(score) do
    :io_lib.format("~.4f", [score]) |> IO.iodata_to_binary()
  end

  defp format_score(score) when is_integer(score), do: format_score(score * 1.0)
end
