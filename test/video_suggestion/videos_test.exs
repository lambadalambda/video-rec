defmodule VideoSuggestion.VideosTest do
  use VideoSuggestion.DataCase

  alias VideoSuggestion.Videos

  import VideoSuggestion.AccountsFixtures

  describe "create_video/1" do
    test "creates a video for a user" do
      user = user_fixture()

      assert {:ok, video} =
               Videos.create_video(%{
                 user_id: user.id,
                 caption: "hello",
                 storage_key: "abc123.mp4",
                 original_filename: "myvideo.mp4",
                 content_type: "video/mp4"
               })

      assert video.user_id == user.id
      assert video.caption == "hello"
      assert video.storage_key == "abc123.mp4"
      assert video.original_filename == "myvideo.mp4"
      assert video.content_type == "video/mp4"
    end
  end

  describe "list_videos/1" do
    test "returns videos newest first" do
      user = user_fixture()

      {:ok, older} = Videos.create_video(%{user_id: user.id, storage_key: "older.mp4"})
      {:ok, newer} = Videos.create_video(%{user_id: user.id, storage_key: "newer.mp4"})

      newer_id = newer.id
      older_id = older.id

      assert [^newer_id, ^older_id] = Videos.list_videos() |> Enum.map(& &1.id)
    end
  end
end
