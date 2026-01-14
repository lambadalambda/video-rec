defmodule VideoSuggestion.RecommendationsTest do
  use VideoSuggestion.DataCase

  alias VideoSuggestion.Interactions
  alias VideoSuggestion.Recommendations
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.VideoEmbedding

  import VideoSuggestion.AccountsFixtures

  @dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  describe "taste_vector_from_favorites/1" do
    test "returns :empty when the user has no favorites" do
      user = user_fixture()
      assert {:error, :empty} = Recommendations.taste_vector_from_favorites(user.id)
    end

    test "returns the normalized mean of favorited video embeddings" do
      user = user_fixture()

      {:ok, a} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "a",
          storage_key: "a.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, b} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "b",
          storage_key: "b.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      set_embedding!(a.id, [1.0, 0.0])
      set_embedding!(b.id, [0.0, 1.0])

      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, a.id)
      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, b.id)

      assert {:ok, taste} = Recommendations.taste_vector_from_favorites(user.id)

      x = Enum.at(taste, 0)
      y = Enum.at(taste, 1)

      assert_in_delta x, :math.sqrt(0.5), 1.0e-6
      assert_in_delta y, :math.sqrt(0.5), 1.0e-6
    end
  end

  describe "rank_videos_for_user/2" do
    test "ranks candidates by similarity and excludes favorited videos" do
      user = user_fixture()

      {:ok, liked} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "liked",
          storage_key: "liked.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, good} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "good",
          storage_key: "good.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, bad} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "bad",
          storage_key: "bad.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      set_embedding!(liked.id, [1.0, 0.0])
      set_embedding!(good.id, [0.9, 0.1])
      set_embedding!(bad.id, [-1.0, 0.0])

      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, liked.id)

      assert {:ok, ranked} = Recommendations.rank_videos_for_user(user.id, limit: 2)
      good_id = good.id
      bad_id = bad.id
      assert [{^good_id, _}, {^bad_id, _}] = ranked

      refute Enum.any?(ranked, fn {id, _score} -> id == liked.id end)
    end
  end

  describe "ranked_feed_video_ids_for_user/2" do
    test "applies MMR diversity to the top of the ranked feed" do
      user = user_fixture()

      {:ok, liked} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "liked",
          storage_key: "liked.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, a} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "a",
          storage_key: "a.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, b} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "b",
          storage_key: "b.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, c} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "c",
          storage_key: "c.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      set_embedding!(liked.id, [1.0, 0.0])
      set_embedding!(a.id, [1.0, 0.0])
      set_embedding!(b.id, [0.99, 0.01])
      set_embedding!(c.id, [0.0, 1.0])

      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, liked.id)

      assert {:ok, ids} =
               Recommendations.ranked_feed_video_ids_for_user(user.id,
                 diversify_lambda: 0.2,
                 diversify_pool_size: 3
               )

      assert ids == [a.id, c.id, b.id]
    end
  end

  describe "taste_vector/1" do
    test "blends favorites with recent watch interactions" do
      user = user_fixture()

      {:ok, favorite} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "fav",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      {:ok, watched} =
        Videos.create_video(%{
          user_id: user.id,
          caption: "watched",
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      set_embedding!(favorite.id, [1.0, 0.0])
      set_embedding!(watched.id, [0.0, 1.0])

      assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, favorite.id)

      assert {:ok, _} =
               Interactions.create_interaction(%{
                 user_id: user.id,
                 video_id: watched.id,
                 event_type: "watch",
                 watch_ms: 100_000
               })

      assert {:ok, taste} = Recommendations.taste_vector(user.id)
      assert Enum.at(taste, 0) < 0.2
      assert Enum.at(taste, 1) > 0.9
    end
  end

  defp set_embedding!(video_id, vector) when is_integer(video_id) and is_list(vector) do
    embedding = Videos.get_video_embedding!(video_id)
    vector = pad_vec(vector)

    {:ok, _} =
      embedding
      |> VideoEmbedding.changeset(%{vector: vector, version: "test"})
      |> Repo.update()

    :ok
  end

  defp pad_vec(values) when is_list(values) do
    values ++ List.duplicate(0.0, max(@dims - length(values), 0))
  end
end
