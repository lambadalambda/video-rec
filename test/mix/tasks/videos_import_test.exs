defmodule Mix.Tasks.Videos.ImportTest do
  use VideoSuggestion.DataCase, async: true

  import ExUnit.CaptureIO

  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  test "imports all videos in a folder" do
    admin = user_fixture()
    assert admin.is_admin

    tmp_dir =
      System.tmp_dir!()
      |> Path.join("video_suggestion_import_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    File.write!(Path.join(tmp_dir, "a.mp4"), "a")
    File.write!(Path.join(tmp_dir, "b.webm"), "b")

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Import.run([tmp_dir, "--user-id", Integer.to_string(admin.id)])
      end)

    videos = Videos.list_videos(limit: 10)
    assert length(videos) == 2

    storage_keys = Enum.map(videos, & &1.storage_key)
    on_exit(fn -> Enum.each(storage_keys, &File.rm_rf(Uploads.path(&1))) end)

    Enum.each(videos, fn video ->
      assert video.user_id == admin.id
      assert is_binary(video.original_filename)
      assert is_binary(video.content_type)
      assert byte_size(video.content_hash) == 32
      assert File.exists?(Uploads.path(video.storage_key))
    end)
  end

  test "skips duplicates in the folder and duplicates already imported" do
    admin = user_fixture()
    assert admin.is_admin

    tmp_dir =
      System.tmp_dir!()
      |> Path.join("video_suggestion_import_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    File.write!(Path.join(tmp_dir, "first.mp4"), "same")
    File.write!(Path.join(tmp_dir, "dup.mp4"), "same")

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Import.run([tmp_dir, "--user-id", Integer.to_string(admin.id)])
      end)

    assert length(Videos.list_videos(limit: 10)) == 1

    _output =
      capture_io(fn ->
        Mix.Tasks.Videos.Import.run([tmp_dir, "--user-id", Integer.to_string(admin.id)])
      end)

    videos = Videos.list_videos(limit: 10)
    assert length(videos) == 1

    storage_keys = Enum.map(videos, & &1.storage_key)
    on_exit(fn -> Enum.each(storage_keys, &File.rm_rf(Uploads.path(&1))) end)
  end
end
