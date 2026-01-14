defmodule VideoSuggestion.EmbeddingWorkerClient do
  @moduledoc false

  @default_base_url "http://127.0.0.1:9001"

  @default_req_options [
    receive_timeout: :timer.minutes(10)
  ]

  @req_options_process_key {:video_suggestion, :embedding_worker_req_options}

  def transcribe_video(storage_key, opts \\ []) when is_binary(storage_key) do
    request(
      :post,
      "/v1/transcribe/video",
      %{storage_key: storage_key},
      opts
    )
  end

  def embed_video(storage_key, attrs \\ %{}, opts \\ [])
      when is_binary(storage_key) and is_map(attrs) do
    attrs = Map.merge(%{storage_key: storage_key}, attrs)

    request(
      :post,
      "/v1/embed/video",
      attrs,
      opts
    )
  end

  def embed_video_frames(frames, attrs \\ %{}, opts \\ [])
      when is_list(frames) and is_map(attrs) do
    caption = Map.get(attrs, :caption) || Map.get(attrs, "caption") || ""
    dims = Map.get(attrs, :dims) || Map.get(attrs, "dims")
    transcript = Map.get(attrs, :transcript) || Map.get(attrs, "transcript")

    fields =
      []
      |> maybe_put_field("caption", caption)
      |> maybe_put_field("dims", dims)
      |> maybe_put_field("transcript", transcript)

    frame_fields =
      frames
      |> Enum.with_index()
      |> Enum.map(fn {frame, idx} ->
        {"frames", {frame, filename: "frame-#{idx}.png", content_type: "image/png"}}
      end)

    request_form_multipart(
      :post,
      "/v1/embed/video_frames",
      fields ++ frame_fields,
      opts
    )
  end

  def embed_text(text, attrs \\ %{}, opts \\ []) when is_binary(text) and is_map(attrs) do
    attrs = Map.merge(%{text: text}, attrs)

    request(
      :post,
      "/v1/embed/text",
      attrs,
      opts
    )
  end

  def transcribe_audio_file(path, opts \\ []) when is_binary(path) do
    request_form_multipart(
      :post,
      "/v1/transcribe/audio",
      [{"audio", File.stream!(path)}],
      opts
    )
  end

  defp request(method, path, json, opts) when is_atom(method) and is_binary(path) do
    {base_url, req_opts} = req_config(opts)

    req_opts =
      req_opts
      |> Keyword.merge(method: method, base_url: base_url, url: path, json: json)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_form_multipart(method, path, fields, opts)
       when is_atom(method) and is_binary(path) and is_list(fields) do
    {base_url, req_opts} = req_config(opts)

    req_opts =
      req_opts
      |> Keyword.merge(method: method, base_url: base_url, url: path, form_multipart: fields)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req_config(opts) do
    req_opts =
      @default_req_options
      |> Keyword.merge(req_options())
      |> Keyword.merge(opts)

    base_url =
      System.get_env("EMBEDDING_WORKER_BASE_URL") ||
        Keyword.get(req_opts, :base_url) ||
        @default_base_url

    {base_url, Keyword.delete(req_opts, :base_url)}
  end

  defp req_options do
    Process.get(@req_options_process_key) ||
      Application.get_env(:video_suggestion, :embedding_worker_req_options, [])
  end

  defp maybe_put_field(fields, _name, nil), do: fields

  defp maybe_put_field(fields, name, value) do
    case to_string(value) |> String.trim() do
      "" -> fields
      value -> fields ++ [{name, value}]
    end
  end
end
