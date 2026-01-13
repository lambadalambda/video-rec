defmodule VideoSuggestionWeb.FeedLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.Interactions
  alias VideoSuggestion.Interactions.Interaction
  alias VideoSuggestion.Videos

  @page_size 50
  @wrap_window 11

  @impl true
  def mount(_params, _session, socket) do
    current_user_id =
      case socket.assigns.current_scope do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    {videos, has_more} =
      Videos.list_videos(limit: @page_size + 1, current_user_id: current_user_id)
      |> take_page(@page_size)

    mode = if has_more, do: :head, else: :full

    {:ok,
     assign(socket,
       videos: videos,
       has_more: has_more,
       mode: mode,
       current_user_id: current_user_id
     )}
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
          data-feed-has-more={to_string(@has_more)}
          data-feed-mode={to_string(@mode)}
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

          <div class="pointer-events-none fixed right-0 bottom-0 z-20 flex flex-col items-center gap-2 p-3">
            <button
              type="button"
              data-feed-play-toggle
              aria-label="Play/pause"
              class="pointer-events-auto btn btn-circle btn-ghost btn-sm"
            >
              <span data-feed-pause-icon>
                <.icon name="hero-pause" class="size-5" />
              </span>
              <span data-feed-play-icon class="hidden">
                <.icon name="hero-play" class="size-5" />
              </span>
            </button>

            <button
              type="button"
              data-feed-sound-toggle
              aria-label="Toggle sound"
              class="pointer-events-auto btn btn-circle btn-ghost btn-sm"
            >
              <span data-feed-sound-off>
                <.icon name="hero-speaker-x-mark" class="size-5" />
              </span>
              <span data-feed-sound-on class="hidden">
                <.icon name="hero-speaker-wave" class="size-5" />
              </span>
            </button>
          </div>

          <%= if @mode == :full and length(@videos) > 1 do %>
            <.feed_item video={List.last(@videos)} current_scope={@current_scope} clone="prev" />
          <% end %>

          <%= for video <- @videos do %>
            <.feed_item video={video} current_scope={@current_scope} />
          <% end %>

          <%= if @mode == :full and length(@videos) > 1 do %>
            <.feed_item video={hd(@videos)} current_scope={@current_scope} clone="next" />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp feed_item(assigns) do
    assigns = assign_new(assigns, :clone, fn -> nil end)

    ~H"""
    <div
      data-feed-item
      data-feed-clone={@clone}
      class="h-dvh snap-start relative flex items-center justify-center bg-black"
    >
      <video
        data-feed-video
        class="h-full w-full object-contain"
        src={"/uploads/" <> @video.storage_key}
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
              data-video-id={@video.id}
              phx-click="toggle-favorite"
              phx-value-id={@video.id}
              aria-label="Favorite"
              class="btn btn-circle btn-ghost btn-sm"
            >
              <.icon
                name={if @video.favorited, do: "hero-heart-solid", else: "hero-heart"}
                class={["size-6", @video.favorited && "text-error"]}
              />
            </button>
          <% else %>
            <.link
              navigate={~p"/users/log-in"}
              data-favorite-button
              data-video-id={@video.id}
              aria-label="Log in to favorite"
              class="btn btn-circle btn-ghost btn-sm"
            >
              <.icon name="hero-heart" class="size-6" />
            </.link>
          <% end %>

          <div data-favorites-count data-video-id={@video.id} class="text-xs font-semibold">
            {@video.favorites_count}
          </div>
        </div>
      </div>

      <div class="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent">
        <div class="p-4 text-sm">
          {@video.caption}
        </div>
      </div>
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

  @impl true
  def handle_event("interaction-batch", %{"events" => events}, socket) when is_list(events) do
    case socket.assigns.current_scope do
      %{user: %{id: user_id}} ->
        Enum.each(events, fn event ->
          case interaction_attrs(event, user_id) do
            {:ok, attrs} -> _ = Interactions.create_interaction(attrs)
            {:error, _} -> :ok
          end
        end)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("interaction-batch", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load-more", _params, socket) do
    cond do
      socket.assigns.mode != :head or socket.assigns.has_more == false ->
        {:noreply, socket}

      socket.assigns.videos == [] ->
        {:noreply, assign(socket, has_more: false, mode: :full)}

      true ->
        last_video = List.last(socket.assigns.videos)

        {more, has_more} =
          Videos.list_videos(
            limit: @page_size + 1,
            current_user_id: socket.assigns.current_user_id,
            before: {last_video.inserted_at, last_video.id}
          )
          |> take_page(@page_size)

        mode = if has_more, do: :head, else: :full

        {:noreply,
         socket
         |> assign(:videos, socket.assigns.videos ++ more)
         |> assign(:has_more, has_more)
         |> assign(:mode, mode)}
    end
  end

  @impl true
  def handle_event("jump-to-end", _params, socket) do
    videos =
      Videos.list_tail_videos(
        limit: @wrap_window,
        current_user_id: socket.assigns.current_user_id
      )

    {:noreply, assign(socket, videos: videos, has_more: false, mode: :tail)}
  end

  @impl true
  def handle_event("jump-to-start", _params, socket) do
    {videos, has_more} =
      Videos.list_videos(limit: @page_size + 1, current_user_id: socket.assigns.current_user_id)
      |> take_page(@page_size)

    mode = if has_more, do: :head, else: :full

    {:noreply, assign(socket, videos: videos, has_more: has_more, mode: mode)}
  end

  defp interaction_attrs(event, user_id) when is_map(event) and is_integer(user_id) do
    type = Map.get(event, "type") || Map.get(event, :type)
    video_id = Map.get(event, "video_id") || Map.get(event, :video_id)
    watch_ms = Map.get(event, "watch_ms") || Map.get(event, :watch_ms)

    with {:ok, video_id} <- cast_int(video_id),
         {:ok, watch_ms} <- cast_optional_int(watch_ms),
         true <- is_binary(type),
         true <- type in Interaction.event_types() do
      attrs = %{user_id: user_id, video_id: video_id, event_type: type}
      attrs = if is_integer(watch_ms), do: Map.put(attrs, :watch_ms, watch_ms), else: attrs
      {:ok, attrs}
    else
      _ -> {:error, :invalid_event}
    end
  end

  defp interaction_attrs(_event, _user_id), do: {:error, :invalid_event}

  defp cast_optional_int(nil), do: {:ok, nil}

  defp cast_optional_int(value) do
    cast_int(value)
  end

  defp cast_int(value) when is_integer(value), do: {:ok, value}

  defp cast_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_int}
    end
  end

  defp cast_int(_value), do: {:error, :invalid_int}

  defp take_page(videos, page_size) when is_list(videos) and is_integer(page_size) do
    {page, rest} = Enum.split(videos, page_size)
    {page, rest != []}
  end
end
