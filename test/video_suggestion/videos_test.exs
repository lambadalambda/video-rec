defmodule VideoSuggestion.VideosTest do
  use VideoSuggestion.DataCase

  alias VideoSuggestion.Repo
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

  describe "transcripts" do
    test "set_video_transcript/2 stores transcript text" do
      user = user_fixture()

      assert {:ok, video} =
               Videos.create_video(%{
                 user_id: user.id,
                 storage_key: "#{System.unique_integer([:positive])}.mp4",
                 content_hash: :crypto.strong_rand_bytes(32)
               })

      assert {:ok, updated} = Videos.set_video_transcript(video.id, "hello world")
      assert updated.transcript == "hello world"
      assert Videos.get_video!(video.id).transcript == "hello world"
    end
  end

  describe "video_embeddings" do
    test "upsert_video_embedding/3 updates the existing embedding record" do
      user = user_fixture()

      assert {:ok, video} =
               Videos.create_video(%{
                 user_id: user.id,
                 storage_key: "#{System.unique_integer([:positive])}.mp4",
                 content_hash: :crypto.strong_rand_bytes(32)
               })

      embedding = Videos.get_video_embedding!(video.id)
      assert embedding.version in ["caption_v1", "hash_v1"]

      assert {:ok, _embedding} =
               Videos.upsert_video_embedding(video.id, "qwen3_vl_v1", [0.0, 1.0])

      embedding = Videos.get_video_embedding!(video.id)
      assert embedding.version == "qwen3_vl_v1"
      assert embedding.vector == [0.0, 1.0]
    end

    test "upsert_video_embedding/3 inserts if the embedding record is missing" do
      user = user_fixture()

      assert {:ok, video} =
               Videos.create_video(%{
                 user_id: user.id,
                 storage_key: "#{System.unique_integer([:positive])}.mp4",
                 content_hash: :crypto.strong_rand_bytes(32)
               })

      embedding = Videos.get_video_embedding!(video.id)
      {:ok, _} = Repo.delete(embedding)

      assert {:ok, _embedding} =
               Videos.upsert_video_embedding(video.id, "qwen3_vl_v1", [0.25, 0.75])

      embedding = Videos.get_video_embedding!(video.id)
      assert embedding.version == "qwen3_vl_v1"
      assert embedding.vector == [0.25, 0.75]
    end
  end

  describe "similar videos" do
    test "similar_videos/2 returns the most similar videos by dot-product" do
      user = user_fixture()

      {:ok, query} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "query",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, good} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "good",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, bad} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "bad",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, _} = Videos.upsert_video_embedding(query.id, "test", [1.0, 0.0])
      {:ok, _} = Videos.upsert_video_embedding(good.id, "test", [0.9, 0.1])
      {:ok, _} = Videos.upsert_video_embedding(bad.id, "test", [-1.0, 0.0])

      assert {:ok, %{version: "test", items: items}} = Videos.similar_videos(query.id, limit: 2)
      assert length(items) == 2

      assert [%{video: first, score: first_score}, %{video: second, score: second_score}] = items
      assert first.id == good.id
      assert second.id == bad.id
      assert first_score > second_score
    end

    test "similar_videos/2 returns :embedding_missing when the query has no embedding" do
      user = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      embedding = Videos.get_video_embedding!(video.id)
      {:ok, _} = Repo.delete(embedding)

      assert {:error, :embedding_missing} = Videos.similar_videos(video.id)
    end

    test "similar_videos/2 compares against embeddings with the same version" do
      user = user_fixture()

      {:ok, query} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "query",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, same_version} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "same",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, other_version} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "other",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, _} = Videos.upsert_video_embedding(query.id, "test", [1.0, 0.0])
      {:ok, _} = Videos.upsert_video_embedding(same_version.id, "test", [1.0, 0.0])
      {:ok, _} = Videos.upsert_video_embedding(other_version.id, "other", [1.0, 0.0])

      assert {:ok, %{items: items}} = Videos.similar_videos(query.id, limit: 10)
      assert Enum.any?(items, &(&1.video.id == same_version.id))
      refute Enum.any?(items, &(&1.video.id == other_version.id))
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
