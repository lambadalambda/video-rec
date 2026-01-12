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

  describe "favorites" do
    test "toggle_favorite/2 favorites and unfavorites a video" do
      user = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4"
        })

      assert Videos.favorites_count(video.id) == 0
      refute Videos.favorited?(user.id, video.id)

      assert {:ok, %{favorited: true, favorites_count: 1}} =
               Videos.toggle_favorite(user.id, video.id)

      assert Videos.favorites_count(video.id) == 1
      assert Videos.favorited?(user.id, video.id)

      assert {:ok, %{favorited: false, favorites_count: 0}} =
               Videos.toggle_favorite(user.id, video.id)

      assert Videos.favorites_count(video.id) == 0
      refute Videos.favorited?(user.id, video.id)
    end

    test "favorites_count/1 counts favorites across users" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user1.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4"
        })

      assert {:ok, %{favorited: true, favorites_count: 1}} =
               Videos.toggle_favorite(user1.id, video.id)

      assert {:ok, %{favorited: true, favorites_count: 2}} =
               Videos.toggle_favorite(user2.id, video.id)

      assert Videos.favorites_count(video.id) == 2
    end
  end
end
