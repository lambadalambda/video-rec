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
                 content_type: "video/mp4",
                 content_hash: :crypto.strong_rand_bytes(32)
               })

      assert video.user_id == user.id
      assert video.caption == "hello"
      assert video.storage_key == "abc123.mp4"
      assert video.original_filename == "myvideo.mp4"
      assert video.content_type == "video/mp4"
    end

    test "creates a deterministic embedding record" do
      user = user_fixture()

      assert {:ok, video} =
               Videos.create_video(%{
                 user_id: user.id,
                 caption: "Cats and dogs",
                 storage_key: "embed.mp4",
                 content_hash: :crypto.strong_rand_bytes(32)
               })

      embedding = Videos.get_video_embedding!(video.id)
      assert embedding.video_id == video.id
      assert embedding.version == "caption_v1"
      assert length(embedding.vector) == VideoSuggestion.Reco.CaptionEmbedding.dims()
    end
  end

  describe "list_videos/1" do
    test "returns videos newest first" do
      user = user_fixture()

      {:ok, older} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "older.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, newer} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "newer.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

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
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
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
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      assert {:ok, %{favorited: true, favorites_count: 1}} =
               Videos.toggle_favorite(user1.id, video.id)

      assert {:ok, %{favorited: true, favorites_count: 2}} =
               Videos.toggle_favorite(user2.id, video.id)

      assert Videos.favorites_count(video.id) == 2
    end
  end

  describe "list_videos/1 (favorites metadata)" do
    test "includes favorites_count and favorited for the current user" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user1.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user1.id, video.id)
      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user2.id, video.id)

      [video_for_user1] = Videos.list_videos(limit: 1, current_user_id: user1.id)
      assert video_for_user1.favorites_count == 2
      assert video_for_user1.favorited == true

      [video_for_anon] = Videos.list_videos(limit: 1)
      assert video_for_anon.favorites_count == 2
      assert video_for_anon.favorited == false
    end
  end
end
