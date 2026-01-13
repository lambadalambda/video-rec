defmodule VideoSuggestionWeb.Admin.VideoSimilarityLive do
  use VideoSuggestionWeb, :live_view

  import Ecto.Query, warn: false

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.Video
  alias VideoSuggestion.Videos.VideoEmbedding
  alias VideoSuggestionWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:videos, [])
     |> assign(:video, nil)
     |> assign(:embedding_version, nil)
     |> assign(:items, [])
     |> assign(:message, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        videos = list_videos()

        {:noreply,
         socket
         |> assign(:videos, videos)
         |> assign(:video, nil)
         |> assign(:embedding_version, nil)
         |> assign(:items, [])
         |> assign(:message, nil)}

      :show ->
        case parse_id(params["id"]) do
          {:ok, id} ->
            video = Repo.get(Video, id)

            if is_nil(video) do
              {:noreply, push_navigate(socket, to: ~p"/admin/similarity")}
            else
              {items, embedding_version, message} = load_similar(video.id)

              {:noreply,
               socket
               |> assign(:video, video)
               |> assign(:embedding_version, embedding_version)
               |> assign(:items, items)
               |> assign(:message, message)}
            end

          :error ->
            {:noreply, push_navigate(socket, to: ~p"/admin/similarity")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Video similarity</.header>

        <%= case @live_action do %>
          <% :index -> %>
            <p class="text-sm opacity-70">
              Pick a video to see the 20 most similar videos by dot-product similarity.
            </p>

            <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
              <div :for={row <- @videos} class="p-4">
                <div class="flex items-start justify-between gap-4">
                  <div class="min-w-0">
                    <div class="font-semibold truncate">{video_label(row.video)}</div>

                    <div class="text-xs opacity-70">
                      embedding: {row.embedding_version || "none"} · dims: {row.embedding_dims}
                    </div>
                  </div>

                  <.link navigate={~p"/admin/similarity/#{row.video.id}"} class="btn btn-ghost btn-xs">
                    Similar
                  </.link>
                </div>
              </div>
            </div>
          <% :show -> %>
            <div class="flex items-center justify-between gap-4">
              <div class="min-w-0">
                <div class="font-semibold truncate">{video_label(@video)}</div>

                <div class="text-xs opacity-70">
                  embedding: {@embedding_version || "none"}
                </div>
              </div>

              <.link navigate={~p"/admin/similarity"} class="btn btn-ghost btn-sm">
                Back
              </.link>
            </div>

            <div class="rounded-box border border-base-300 bg-base-100 overflow-hidden">
              <video
                class="w-full aspect-video bg-black"
                src={Uploads.url(@video.storage_key)}
                playsinline
                muted
                controls
              >
              </video>
            </div>

            <%= if @items == [] do %>
              <p class="text-sm opacity-70">{@message}</p>
            <% else %>
              <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
                <div :for={item <- @items} class="p-4">
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

                  <div class="mt-3 rounded-box border border-base-300 bg-base-200 overflow-hidden">
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

  defp list_videos do
    from(v in Video,
      left_join: e in VideoEmbedding,
      on: e.video_id == v.id,
      order_by: [desc: v.inserted_at, desc: v.id],
      select: %{
        video: v,
        embedding_version: e.version,
        embedding_dims: fragment("COALESCE(array_length(?, 1), 0)", e.vector)
      }
    )
    |> Repo.all()
  end

  defp load_similar(video_id) do
    case Videos.similar_videos(video_id, limit: 20) do
      {:ok, %{version: version, items: items}} ->
        message =
          if items == [] do
            "No comparable videos found for embedding version #{inspect(version)}."
          else
            nil
          end

        {items, version, message}

      {:error, :embedding_missing} ->
        {[], nil, "This video has no embedding yet. Run mix videos.embed_visual."}

      {:error, :empty_vector} ->
        {[], nil, "This video's embedding vector is empty."}
    end
  end

  defp parse_id(nil), do: :error

  defp parse_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp video_label(%Video{} = video) do
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
