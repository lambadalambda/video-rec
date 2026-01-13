defmodule Mix.Tasks.Videos.TranscribeTest do
  use VideoSuggestion.DataCase, async: true

  import ExUnit.CaptureIO
  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  setup do
    stub_name = __MODULE__

    Req.Test.stub(stub_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/transcribe/video"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          %{"storage_key" => storage_key} = Jason.decode!(body)
          Req.Test.json(conn, %{transcript: "tx:#{storage_key}"})

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

  test "transcribes videos missing a transcript" do
    user = user_fixture()

    storage_key = "#{System.unique_integer([:positive])}.mp4"

    assert {:ok, video} =
             Videos.create_video(%{
               user_id: user.id,
               storage_key: storage_key,
               content_hash: :crypto.strong_rand_bytes(32)
             })

    Uploads.ensure_dir!()
    File.write!(Uploads.path(storage_key), "fake")
    on_exit(fn -> File.rm_rf(Uploads.path(storage_key)) end)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Transcribe.run([])
      end)

    assert Videos.get_video!(video.id).transcript == "tx:#{storage_key}"
  end

  test "skips videos with transcript unless --force is set" do
    user = user_fixture()

    storage_key = "#{System.unique_integer([:positive])}.mp4"

    assert {:ok, video} =
             Videos.create_video(%{
               user_id: user.id,
               storage_key: storage_key,
               transcript: "already",
               content_hash: :crypto.strong_rand_bytes(32)
             })

    Uploads.ensure_dir!()
    File.write!(Uploads.path(storage_key), "fake")
    on_exit(fn -> File.rm_rf(Uploads.path(storage_key)) end)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Transcribe.run([])
      end)

    assert Videos.get_video!(video.id).transcript == "already"

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Transcribe.run(["--force"])
      end)

    assert Videos.get_video!(video.id).transcript == "tx:#{storage_key}"
  end

  test "stores empty transcripts and does not retry them without --force" do
    user = user_fixture()

    storage_key = "#{System.unique_integer([:positive])}.mp4"

    assert {:ok, video} =
             Videos.create_video(%{
               user_id: user.id,
               storage_key: storage_key,
               content_hash: :crypto.strong_rand_bytes(32)
             })

    Uploads.ensure_dir!()
    File.write!(Uploads.path(storage_key), "fake")
    on_exit(fn -> File.rm_rf(Uploads.path(storage_key)) end)

    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/transcribe/video"} ->
          send(test_pid, {:transcribe_called, conn.request_path})
          Req.Test.json(conn, %{transcript: ""})

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Transcribe.run([])
      end)

    assert_receive {:transcribe_called, _}
    assert Videos.get_video!(video.id).transcript == ""

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Transcribe.run([])
      end)

    refute_receive {:transcribe_called, _}, 50
  end
end
