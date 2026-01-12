defmodule VideoSuggestionWeb.Admin.VideoUploadLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(caption: nil, uploaded_count: 0, duplicate_count: 0, failure_count: 0)
      |> assign(seen_hashes: MapSet.new())
      |> assign(processed_entry_refs: MapSet.new(), pending_uploads: [])
      |> assign(form: to_form(%{}, as: "video"))
      |> allow_upload(:video,
        accept: ~w(.mp4 .m4v .mov .webm),
        auto_upload: true,
        max_entries: 1000,
        max_file_size: 200_000_000,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Upload video</.header>

        <.form for={@form} id="video_upload_form" phx-submit="save" phx-change="validate" multipart>
          <.input field={@form[:caption]} type="text" label="Caption" />

          <label class="form-control w-full">
            <div class="label">
              <span class="label-text">Video file</span>
            </div>
            <.live_file_input upload={@uploads.video} class="file-input file-input-bordered w-full" />
          </label>

          <section phx-drop-target={@uploads.video.ref} class="space-y-2">
            <article :for={entry <- @uploads.video.entries} class="card bg-base-200 p-3 space-y-2">
              <div class="flex items-center justify-between gap-3">
                <div class="text-sm truncate">{entry.client_name}</div>

                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                >
                  Cancel
                </button>
              </div>

              <progress value={entry.progress} max="100" class="progress progress-primary w-full">
                {entry.progress}%
              </progress>

              <p :for={err <- upload_errors(@uploads.video, entry)} class="text-error text-xs">
                {error_to_string(err)}
              </p>
            </article>

            <p :for={err <- upload_errors(@uploads.video)} class="text-error text-xs">
              {error_to_string(err)}
            </p>
          </section>

          <.button
            phx-disable-with="Uploading..."
            class="btn btn-primary w-full"
            disabled={
              Enum.any?(@uploads.video.entries, &(&1.progress < 100)) or
                upload_errors(@uploads.video) != [] or
                Enum.any?(@uploads.video.entries, fn entry ->
                  upload_errors(@uploads.video, entry) != []
                end)
            }
          >
            Upload
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"video" => %{"caption" => caption}}, socket) do
    {:noreply, assign(socket, caption: caption)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :video, ref)}
  end

  @impl true
  def handle_event("save", %{"video" => video_params}, socket) do
    _caption = Map.get(video_params, "caption")

    {completed, in_progress} = uploaded_entries(socket, :video)

    cond do
      in_progress != [] ->
        {:noreply,
         put_flash(socket, :error, "Upload still in progress. Please wait for it to finish.")}

      completed == [] ->
        if Enum.empty?(socket.assigns.pending_uploads) and socket.assigns.duplicate_count == 0 do
          {:noreply, put_flash(socket, :error, "Please choose a video file to upload.")}
        else
          {:noreply, push_navigate(socket, to: ~p"/")}
        end

      true ->
        uploader = socket.assigns.current_scope.user

        {created_count, duplicate_count, failure_count} =
          Enum.reduce(
            socket.assigns.pending_uploads,
            {0, socket.assigns.duplicate_count, 0},
            fn attrs, {created_count, duplicate_count, failure_count} ->
              storage_path = Uploads.path(attrs.storage_key)

              case Videos.create_video(%{
                     user_id: uploader.id,
                     caption: video_params["caption"],
                     storage_key: attrs.storage_key,
                     original_filename: attrs.original_filename,
                     content_type: attrs.content_type,
                     content_hash: attrs.content_hash
                   }) do
                {:ok, _video} ->
                  {created_count + 1, duplicate_count, failure_count}

                {:error, %Ecto.Changeset{} = changeset} ->
                  File.rm_rf(storage_path)

                  if changeset.errors[:content_hash] do
                    {created_count, duplicate_count + 1, failure_count}
                  else
                    {created_count, duplicate_count, failure_count + 1}
                  end
              end
            end
          )

        message =
          cond do
            created_count > 0 and duplicate_count > 0 ->
              "Uploaded #{created_count} video(s). Skipped #{duplicate_count} duplicate(s)."

            created_count > 0 ->
              "Uploaded #{created_count} video(s)."

            duplicate_count > 0 and failure_count == 0 ->
              "All selected videos were duplicates."

            true ->
              "Upload failed."
          end

        socket =
          if created_count == 0 and failure_count > 0 do
            put_flash(socket, :error, message)
          else
            put_flash(socket, :info, message)
          end

        if created_count > 0 do
          {:noreply, socket |> push_navigate(to: ~p"/")}
        else
          {:noreply, socket}
        end
    end
  end

  def handle_progress(:video, entry, socket) do
    if entry.done? do
      if MapSet.member?(socket.assigns.processed_entry_refs, entry.ref) do
        {:noreply, socket}
      else
        result =
          consume_uploaded_entry(socket, entry, fn %{path: path} ->
            ext = Path.extname(entry.client_name) |> String.downcase()
            storage_key = entry.uuid <> ext
            content_hash = Uploads.sha256_file(path)

            cond do
              MapSet.member?(socket.assigns.seen_hashes, content_hash) ->
                {:postpone, {:duplicate, content_hash}}

              Videos.content_hash_exists?(content_hash) ->
                {:postpone, {:duplicate, content_hash}}

              true ->
                Uploads.ensure_dir!()
                File.cp!(path, Uploads.path(storage_key))

                {:postpone,
                 {:pending,
                  %{
                    storage_key: storage_key,
                    original_filename: entry.client_name,
                    content_type: entry.client_type,
                    content_hash: content_hash
                  }}}
            end
          end)

        socket =
          socket
          |> assign(
            :processed_entry_refs,
            MapSet.put(socket.assigns.processed_entry_refs, entry.ref)
          )

        case result do
          {:pending, attrs} ->
            {:noreply,
             socket
             |> assign(:pending_uploads, [attrs | socket.assigns.pending_uploads])
             |> assign(:seen_hashes, MapSet.put(socket.assigns.seen_hashes, attrs.content_hash))}

          {:duplicate, _content_hash} ->
            {:noreply, assign(socket, :duplicate_count, socket.assigns.duplicate_count + 1)}
        end
      end
    else
      {:noreply, socket}
    end
  end

  defp error_to_string(:too_large), do: "File too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
