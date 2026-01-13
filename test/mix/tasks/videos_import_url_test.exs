defmodule Mix.Tasks.Videos.ImportUrlTest do
  use VideoSuggestion.DataCase, async: true

  import ExUnit.CaptureIO
  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  setup do
    stub_name = __MODULE__

    Req.Test.stub(stub_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/wsg/thread/6067049.json"} ->
          Req.Test.json(conn, %{
            "posts" => [
              %{"tim" => 1, "ext" => ".webm", "filename" => "alpha"},
              %{"tim" => 2, "ext" => ".mp4", "filename" => "beta"}
            ]
          })

        {"GET", "/wsg/1.webm"} ->
          Plug.Conn.send_resp(conn, 200, "webm-bytes")

        {"GET", "/wsg/2.mp4"} ->
          Plug.Conn.send_resp(conn, 200, "mp4-bytes")

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)

    Process.put({:video_suggestion, :videos_import_req_options},
      plug: {Req.Test, stub_name},
      base_url: "https://a.4cdn.org"
    )

    on_exit(fn ->
      Process.delete({:video_suggestion, :videos_import_req_options})
      System.delete_env("FFMPEG_BIN")
    end)

    :ok
  end

  test "imports videos from a 4chan thread url" do
    admin = user_fixture()
    assert admin.is_admin

    ffmpeg = write_fake_ffmpeg!()
    System.put_env("FFMPEG_BIN", ffmpeg)

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.ImportUrl.run([
          "https://boards.4chan.org/wsg/thread/6067049",
          "--user-id",
          Integer.to_string(admin.id)
        ])
      end)

    videos = Videos.list_videos(limit: 10)
    assert length(videos) == 2

    storage_keys = Enum.map(videos, & &1.storage_key)
    on_exit(fn -> Enum.each(storage_keys, &File.rm_rf(Uploads.path(&1))) end)

    Enum.each(videos, fn video ->
      assert video.user_id == admin.id
      assert video.content_type == "video/mp4"
      assert Path.extname(video.storage_key) == ".mp4"
      assert byte_size(video.content_hash) == 32
      assert File.exists?(Uploads.path(video.storage_key))
    end)

    captions = Enum.map(videos, & &1.caption) |> Enum.sort()
    assert captions == ["alpha", "beta"]
  end

  test "skips duplicates when running twice" do
    admin = user_fixture()
    assert admin.is_admin

    ffmpeg = write_fake_ffmpeg!()
    System.put_env("FFMPEG_BIN", ffmpeg)

    capture_io(fn ->
      Mix.Tasks.Videos.ImportUrl.run([
        "https://boards.4chan.org/wsg/thread/6067049",
        "--user-id",
        Integer.to_string(admin.id)
      ])
    end)

    assert length(Videos.list_videos(limit: 10)) == 2

    capture_io(fn ->
      Mix.Tasks.Videos.ImportUrl.run([
        "https://boards.4chan.org/wsg/thread/6067049",
        "--user-id",
        Integer.to_string(admin.id)
      ])
    end)

    videos = Videos.list_videos(limit: 10)
    assert length(videos) == 2

    storage_keys = Enum.map(videos, & &1.storage_key)
    on_exit(fn -> Enum.each(storage_keys, &File.rm_rf(Uploads.path(&1))) end)
  end

  defp write_fake_ffmpeg! do
    dir =
      System.tmp_dir!()
      |> Path.join("video_suggestion_ffmpeg_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    path = Path.join(dir, "ffmpeg")

    File.write!(
      path,
      """
      #!/bin/sh
      set -e
      in=""
      out=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-i" ]; then
          shift
          in="$1"
        fi
        out="$1"
        shift
      done
      if [ -z "$in" ] || [ -z "$out" ]; then
        exit 1
      fi
      cp "$in" "$out"
      """
    )

    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf(dir) end)

    path
  end
end
