defmodule VideoSuggestionWeb.FeedLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.Videos

  @impl true
  def mount(_params, _session, socket) do
    current_user_id =
      case socket.assigns.current_scope do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    {:ok, assign(socket, videos: Videos.list_videos(current_user_id: current_user_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative h-dvh bg-black text-white">
      <div class="pointer-events-none absolute inset-x-0 top-0 z-10 bg-gradient-to-b from-black/70 to-transparent">
        <div class="pointer-events-auto flex items-center justify-between p-3">
          <div class="text-sm font-semibold">For You</div>

          <div class="flex items-center gap-3 text-sm">
            <%= if @current_scope && @current_scope.user do %>
              <%= if @current_scope.user.is_admin do %>
                <.link navigate={~p"/admin/videos/new"} class="underline">Upload</.link>
              <% end %>

              <span class="hidden sm:block text-xs opacity-70">
                {@current_scope.user.email}
              </span>

              <.link navigate={~p"/users/settings"} class="underline">Settings</.link>
              <.link href={~p"/users/log-out"} method="delete" class="underline">Log out</.link>
            <% else %>
              <.link navigate={~p"/users/log-in"} class="underline">Log in</.link>
            <% end %>
          </div>
        </div>
      </div>

      <%= if Enum.empty?(@videos) do %>
        <div class="h-dvh flex items-center justify-center opacity-80">
          No videos yet.
        </div>
      <% else %>
        <div
          id="feed"
          phx-hook="VideoFeed"
          class="h-dvh overflow-y-scroll snap-y snap-mandatory no-scrollbar"
        >
          <div class="pointer-events-none fixed inset-y-0 right-0 z-20 hidden sm:flex flex-col justify-center gap-2 p-3">
            <button
              type="button"
              data-feed-prev
              aria-label="Previous video"
              class="pointer-events-auto btn btn-circle btn-ghost btn-sm"
            >
              <.icon name="hero-chevron-up" class="size-5" />
            </button>

            <button
              type="button"
              data-feed-next
              aria-label="Next video"
              class="pointer-events-auto btn btn-circle btn-ghost btn-sm"
            >
              <.icon name="hero-chevron-down" class="size-5" />
            </button>
          </div>

          <%= for video <- @videos do %>
            <div
              data-feed-item
              class="h-dvh snap-start relative flex items-center justify-center bg-black"
            >
              <video
                data-feed-video
                class="h-full w-full object-contain"
                src={"/uploads/" <> video.storage_key}
                playsinline
                muted
                loop
                preload="metadata"
              >
              </video>

              <div class="pointer-events-none absolute inset-0">
                <div class="pointer-events-auto absolute right-3 bottom-24 flex flex-col items-center gap-1">
                  <%= if @current_scope && @current_scope.user do %>
                    <button
                      type="button"
                      data-favorite-button
                      data-video-id={video.id}
                      phx-click="toggle-favorite"
                      phx-value-id={video.id}
                      aria-label="Favorite"
                      class="btn btn-circle btn-ghost btn-sm"
                    >
                      <.icon
                        name={if video.favorited, do: "hero-heart-solid", else: "hero-heart"}
                        class={["size-6", video.favorited && "text-error"]}
                      />
                    </button>
                  <% else %>
                    <.link
                      navigate={~p"/users/log-in"}
                      data-favorite-button
                      data-video-id={video.id}
                      aria-label="Log in to favorite"
                      class="btn btn-circle btn-ghost btn-sm"
                    >
                      <.icon name="hero-heart" class="size-6" />
                    </.link>
                  <% end %>

                  <div data-favorites-count data-video-id={video.id} class="text-xs font-semibold">
                    {video.favorites_count}
                  </div>
                </div>
              </div>

              <div class="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent">
                <div class="p-4 text-sm">
                  {video.caption}
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    case socket.assigns.current_scope do
      %{user: %{id: user_id}} ->
        video_id = String.to_integer(id)

        {:ok, %{favorited: favorited, favorites_count: favorites_count}} =
          Videos.toggle_favorite(user_id, video_id)

        videos =
          Enum.map(socket.assigns.videos, fn video ->
            if video.id == video_id do
              %{video | favorited: favorited, favorites_count: favorites_count}
            else
              video
            end
          end)

        {:noreply, assign(socket, videos: videos)}

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
    end
  end
end
