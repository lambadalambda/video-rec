defmodule VideoSuggestion.TagsTest do
  use VideoSuggestion.DataCase, async: true

  alias VideoSuggestion.Tags
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.VideoEmbedding

  defmodule FakeEmbeddingClient do
    def embed_text(text, %{dims: 2}) do
      text = String.downcase(String.trim(to_string(text)))

      embedding =
        case text do
          "cats" -> [1.0, 0.0]
          "dogs" -> [0.0, 1.0]
          _ -> [0.0, 1.0]
        end

      {:ok, %{"version" => "qwen3_vl_v1", "dims" => 2, "embedding" => embedding}}
    end
  end

  test "ingest_tags/2 normalizes, dedupes, and stores embeddings" do
    assert :ok =
             Tags.ingest_tags(
               [" Cats ", "dogs", "cats", "", "   ", "# ignore-me"],
               dims: 2,
               embedding_client: FakeEmbeddingClient
             )

    tags = Repo.all(from t in Tag, order_by: t.name)
    assert Enum.map(tags, & &1.name) == ["cats", "dogs"]
    assert Enum.map(tags, & &1.vector) == [[1.0, 0.0], [0.0, 1.0]]
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

    {:ok, _} = Videos.upsert_video_embedding(v1.id, "qwen3_vl_v1", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(v2.id, "qwen3_vl_v1", [0.0, 1.0])

    assert :ok =
             Tags.ingest_tags(["cats", "dogs"], dims: 2, embedding_client: FakeEmbeddingClient)

    assert {:ok, %{updated_videos: 2}} =
             Tags.refresh_video_tag_suggestions(
               top_k: 1,
               video_version_prefix: "qwen3_vl",
               tag_version_prefix: "qwen3_vl"
             )

    assert {:ok, [%{tag: "cats"}]} = Tags.likely_tags(v1.id, limit: 1)
    assert {:ok, [%{tag: "dogs"}]} = Tags.likely_tags(v2.id, limit: 1)

    assert Repo.aggregate(VideoEmbedding, :count, :id) == 2
  end
end
