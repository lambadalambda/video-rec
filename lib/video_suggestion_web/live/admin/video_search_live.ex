defmodule VideoSuggestionWeb.Admin.VideoSearchLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.EmbeddingWorkerClient
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos
  alias VideoSuggestionWeb.Layouts

  @limit 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:query_version, nil)
     |> assign(:query_dims, nil)
     |> assign(:items, [])
     |> assign(:message, "Enter a query to search by embedding similarity.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Video search</.header>

        <form id="video_search_form" phx-submit="search" class="flex gap-2">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search query…"
            class="input input-bordered w-full"
          />
          <button type="submit" class="btn btn-primary">Search</button>
        </form>

        <%= if is_binary(@query_version) and is_integer(@query_dims) do %>
          <p class="text-xs opacity-70">
            query embedding: {@query_version} · dims: {@query_dims}
          </p>
        <% end %>

        <%= if @items == [] do %>
          <p class="text-sm opacity-70">{@message}</p>
        <% else %>
          <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
            <div :for={item <- @items} class="p-4 space-y-3">
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="font-semibold truncate">
                    {item.video.caption || item.video.storage_key}
                  </div>
                  <div class="text-xs opacity-70">score: {format_score(item.score)}</div>
                </div>

                <.link navigate={~p"/admin/similarity/#{item.video.id}"} class="btn btn-ghost btn-xs">
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
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    query = q |> to_string() |> String.trim()

    if query == "" do
      {:noreply,
       socket
       |> assign(:query, "")
       |> assign(:items, [])
       |> assign(:query_version, nil)
       |> assign(:query_dims, nil)
       |> assign(:message, "Enter a query to search by embedding similarity.")}
    else
      case EmbeddingWorkerClient.embed_text(query) do
        {:ok, %{"version" => version, "dims" => dims, "embedding" => embedding}}
        when is_binary(version) and is_integer(dims) and is_list(embedding) ->
          {items, message} =
            case Videos.search_videos_by_embedding(embedding, search_opts_for_version(version)) do
              {:ok, items} ->
                {items, if(items == [], do: "No matching videos found.", else: nil)}

              {:error, :empty_vector} ->
                {[], "Query embedding was empty."}
            end

          {:noreply,
           socket
           |> assign(:query, query)
           |> assign(:query_version, version)
           |> assign(:query_dims, dims)
           |> assign(:items, items)
           |> assign(:message, message)}

        {:ok, _unexpected} ->
          {:noreply,
           socket
           |> assign(:query, query)
           |> assign(:items, [])
           |> assign(:query_version, nil)
           |> assign(:query_dims, nil)
           |> assign(:message, "Unexpected embedding worker response.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:query, query)
           |> assign(:items, [])
           |> assign(:query_version, nil)
           |> assign(:query_dims, nil)
           |> assign(:message, "Embedding worker unavailable. Is it running?")}
      end
    end
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  defp search_opts_for_version(version) when is_binary(version) do
    base = version |> String.trim() |> String.downcase()

    opts = [limit: @limit]

    if String.starts_with?(base, "qwen3_vl") do
      Keyword.put(opts, :version_prefix, "qwen3_vl")
    else
      Keyword.put(opts, :version, version)
    end
  end

  defp format_score(score) when is_float(score) do
    :io_lib.format("~.4f", [score]) |> IO.iodata_to_binary()
  end

  defp format_score(score) when is_integer(score), do: format_score(score * 1.0)
end
