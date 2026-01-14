defmodule VideoSuggestion.EmbeddingWorkerClientTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.EmbeddingWorkerClient

  setup do
    stub_name = __MODULE__

    Req.Test.stub(stub_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/embed/text"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          if payload["text"] == "hello" and payload["dims"] == 2 do
            Req.Test.json(conn, %{version: "qwen3_vl_v1", dims: 2, embedding: [1.0, 0.0]})
          else
            Plug.Conn.send_resp(conn, 400, "unexpected payload")
          end

        {"POST", "/v1/embed/video_frames"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          if body =~ "name=\"caption\"" and body =~ "hello" and body =~ "name=\"frames\"" do
            Req.Test.json(conn, %{version: "qwen3_vl_v1", dims: 2, embedding: [0.0, 1.0]})
          else
            Plug.Conn.send_resp(conn, 400, "unexpected payload")
          end

        {"POST", "/v1/transcribe/audio"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          if body =~ "name=\"audio\"" and body =~ "audio-bytes" do
            Req.Test.json(conn, %{transcript: "ok"})
          else
            Plug.Conn.send_resp(conn, 400, "unexpected payload")
          end

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)

    Process.put({:video_suggestion, :embedding_worker_req_options},
      plug: {Req.Test, stub_name},
      base_url: "http://embedding-worker"
    )

    on_exit(fn ->
      Process.delete({:video_suggestion, :embedding_worker_req_options})
    end)

    :ok
  end

  test "embed_text/2 posts to the embedding worker" do
    assert {:ok, %{"version" => "qwen3_vl_v1", "embedding" => [1.0, +0.0]}} =
             EmbeddingWorkerClient.embed_text("hello", %{dims: 2})
  end

  test "embed_video_frames/2 posts multipart frames" do
    frames = ["fake-frame"]

    assert {:ok, %{"version" => "qwen3_vl_v1", "embedding" => [+0.0, 1.0]}} =
             EmbeddingWorkerClient.embed_video_frames(frames, %{caption: "hello", dims: 2})
  end

  test "transcribe_audio_file/1 posts multipart audio" do
    path = Path.join(System.tmp_dir!(), "embedding_worker_client_test_audio.wav")

    try do
      File.write!(path, "audio-bytes")

      assert {:ok, %{"transcript" => "ok"}} = EmbeddingWorkerClient.transcribe_audio_file(path)
    after
      File.rm_rf(path)
    end
  end
end
