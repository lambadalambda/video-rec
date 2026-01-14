defmodule VideoSuggestion.TagsTest do
  use VideoSuggestion.DataCase, async: true

  alias VideoSuggestion.Tags
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.VideoEmbedding

  @dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  defmodule FakeEmbeddingClient do
    def embed_text(text, %{dims: dims}) when is_integer(dims) and dims > 0 do
      text = String.downcase(String.trim(to_string(text)))

      base =
        case text do
          "cats" -> [1.0, 0.0]
          "dogs" -> [0.0, 1.0]
          _ -> [0.0, 1.0]
        end

      embedding = base ++ List.duplicate(0.0, max(dims - length(base), 0))

      {:ok, %{"version" => "qwen3_vl_v1", "dims" => dims, "embedding" => embedding}}
    end
  end

  test "ingest_tags/2 normalizes, dedupes, and stores embeddings" do
    assert :ok =
             Tags.ingest_tags(
               [" Cats ", "dogs", "cats", "", "   ", "# ignore-me"],
               dims: @dims,
               embedding_client: FakeEmbeddingClient
             )

    tags = Repo.all(from t in Tag, order_by: t.name)
    assert Enum.map(tags, & &1.name) == ["cats", "dogs"]
    assert Enum.map(tags, &Pgvector.to_list(&1.vector)) ==
             [pad_vec([1.0, 0.0]), pad_vec([0.0, 1.0])]

    assert Enum.all?(tags, &(&1.version == "qwen3_vl_v1"))
  end

  test "refresh_video_tag_suggestions/1 stores top-K tags per video embedding" do
    user = VideoSuggestion.AccountsFixtures.user_fixture()

    {:ok, v1} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v1",
        storage_key: "v1.mp4",
        original_filename: "v1.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v2} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v2",
        storage_key: "v2.mp4",
        original_filename: "v2.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(v1.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))
    {:ok, _} = Videos.upsert_video_embedding(v2.id, "qwen3_vl_v1", pad_vec([0.0, 1.0]))

    assert :ok =
             Tags.ingest_tags(["cats", "dogs"], dims: @dims, embedding_client: FakeEmbeddingClient)

    assert {:ok, %{updated_videos: 2}} =
             Tags.refresh_video_tag_suggestions(
               top_k: 1,
               video_version_prefix: "qwen3_vl",
               tag_version_prefix: "qwen3_vl"
             )

    assert {:ok, [%{id: cats_id, tag: "cats"}]} = Tags.likely_tags(v1.id, limit: 1)
    assert {:ok, [%{id: dogs_id, tag: "dogs"}]} = Tags.likely_tags(v2.id, limit: 1)

    assert is_integer(cats_id) and cats_id > 0
    assert is_integer(dogs_id) and dogs_id > 0

    assert Repo.aggregate(VideoEmbedding, :count, :id) == 2
  end

  test "list_tags_by_frequency/0 orders by suggestion count and returns counts" do
    user = VideoSuggestion.AccountsFixtures.user_fixture()

    {:ok, v1} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v1",
        storage_key: "v1.mp4",
        original_filename: "v1.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v2} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v2",
        storage_key: "v2.mp4",
        original_filename: "v2.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v3} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v3",
        storage_key: "v3.mp4",
        original_filename: "v3.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(v1.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))
    {:ok, _} = Videos.upsert_video_embedding(v2.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))
    {:ok, _} = Videos.upsert_video_embedding(v3.id, "qwen3_vl_v1", pad_vec([0.0, 1.0]))

    assert :ok =
             Tags.ingest_tags(["cats", "dogs"], dims: @dims, embedding_client: FakeEmbeddingClient)

    assert {:ok, %{updated_videos: 3}} = Tags.refresh_video_tag_suggestions(top_k: 1)

    [%{tag: t1, count: c1}, %{tag: t2, count: c2}] = Tags.list_tags_by_frequency()
    assert {t1, c1} == {"cats", 2}
    assert {t2, c2} == {"dogs", 1}
  end

  test "list_videos_for_tag/2 returns videos ranked by similarity score" do
    user = VideoSuggestion.AccountsFixtures.user_fixture()

    {:ok, v1} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v1",
        storage_key: "v1.mp4",
        original_filename: "v1.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v2} =
      Videos.create_video(%{
        user_id: user.id,
        caption: "v2",
        storage_key: "v2.mp4",
        original_filename: "v2.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(v1.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))
    {:ok, _} = Videos.upsert_video_embedding(v2.id, "qwen3_vl_v1", pad_vec([0.8, 0.2]))

    assert :ok =
             Tags.ingest_tags(["cats"], dims: @dims, embedding_client: FakeEmbeddingClient)

    assert {:ok, %{updated_videos: 2}} = Tags.refresh_video_tag_suggestions(top_k: 1)

    cats = Repo.get_by!(Tag, name: "cats")
    [item1, item2] = Tags.list_videos_for_tag(cats.id, limit: 10)

    assert item1.video.id == v1.id
    assert item2.video.id == v2.id
    assert item1.score > item2.score
  end

  defp pad_vec(values) when is_list(values) do
    values ++ List.duplicate(0.0, max(@dims - length(values), 0))
  end
end
