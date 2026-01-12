defmodule VideoSuggestionWeb.Admin.VideoUploadLive do
  use VideoSuggestionWeb, :live_view

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(form: to_form(%{}, as: "video"))
      |> allow_upload(:video,
        accept: ~w(.mp4 .mov .webm),
        max_entries: 1,
        max_file_size: 200_000_000
      )

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>Upload video</.header>

        <.form for={@form} id="video_upload_form" phx-submit="save">
          <.input field={@form[:caption]} type="text" label="Caption" />

          <label class="form-control w-full">
            <div class="label">
              <span class="label-text">Video file</span>
            </div>
            <.live_file_input upload={@uploads.video} class="file-input file-input-bordered w-full" />
          </label>

          <.button phx-disable-with="Uploading..." class="btn btn-primary w-full">
            Upload
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"video" => video_params}, socket) do
    uploader = socket.assigns.current_scope.user
    caption = Map.get(video_params, "caption")

    results =
      consume_uploaded_entries(socket, :video, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name) |> String.downcase()
        storage_key = entry.uuid <> ext

        Uploads.ensure_dir!()
        File.cp!(path, Uploads.path(storage_key))

        {:ok,
         %{
           storage_key: storage_key,
           original_filename: entry.client_name,
           content_type: entry.client_type
         }}
      end)

    case results do
      [
        %{
          storage_key: storage_key,
          original_filename: original_filename,
          content_type: content_type
        }
      ] ->
        case Videos.create_video(%{
               user_id: uploader.id,
               caption: caption,
               storage_key: storage_key,
               original_filename: original_filename,
               content_type: content_type
             }) do
          {:ok, _video} ->
            {:noreply,
             socket
             |> put_flash(:info, "Uploaded!")
             |> push_navigate(to: ~p"/")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, "Upload failed: #{inspect(changeset.errors)}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "Please choose a video file to upload.")}
    end
  end
end
