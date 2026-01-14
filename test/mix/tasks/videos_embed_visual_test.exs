defmodule Mix.Tasks.Videos.EmbedVisualTest do
  use VideoSuggestion.DataCase, async: true

  import ExUnit.CaptureIO
  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  @dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  setup do
    stub_name = __MODULE__

    Req.Test.stub(stub_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/embed/video"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          if payload["transcribe"] != false do
            Plug.Conn.send_resp(conn, 400, "expected transcribe=false")
          else
            Req.Test.json(conn, %{
              version: "qwen3_vl_v1",
              dims: @dims,
              embedding: pad_vec([0.25, 0.75])
            })
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

  test "computes embeddings and stores them in video_embeddings" do
    user = user_fixture()

    storage_key = "#{System.unique_integer([:positive])}.mp4"

    assert {:ok, video} =
             Videos.create_video(%{
               user_id: user.id,
               storage_key: storage_key,
               caption: "hello",
               content_hash: :crypto.strong_rand_bytes(32)
             })

    Uploads.ensure_dir!()
    File.write!(Uploads.path(storage_key), "fake")
    on_exit(fn -> File.rm_rf(Uploads.path(storage_key)) end)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.EmbedVisual.run([])
      end)

    embedding = Videos.get_video_embedding!(video.id)
    assert embedding.version == "qwen3_vl_v1"
    assert Pgvector.to_list(embedding.vector) == pad_vec([0.25, 0.75])
  end

  test "skips videos already embedded with qwen3_vl_v1 unless --force" do
    user = user_fixture()

    storage_key = "#{System.unique_integer([:positive])}.mp4"

    assert {:ok, video} =
             Videos.create_video(%{
               user_id: user.id,
               storage_key: storage_key,
               content_hash: :crypto.strong_rand_bytes(32)
             })

    assert {:ok, _} = Videos.upsert_video_embedding(video.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))

    Uploads.ensure_dir!()
    File.write!(Uploads.path(storage_key), "fake")
    on_exit(fn -> File.rm_rf(Uploads.path(storage_key)) end)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.EmbedVisual.run([])
      end)

    embedding = Videos.get_video_embedding!(video.id)
    assert Pgvector.to_list(embedding.vector) == pad_vec([1.0, 0.0])

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.EmbedVisual.run(["--force"])
      end)

    embedding = Videos.get_video_embedding!(video.id)
    assert Pgvector.to_list(embedding.vector) == pad_vec([0.25, 0.75])
  end

  defp pad_vec(values) when is_list(values) do
    values ++ List.duplicate(0.0, max(@dims - length(values), 0))
  end
end
