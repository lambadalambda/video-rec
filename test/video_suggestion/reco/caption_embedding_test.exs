defmodule VideoSuggestion.Reco.CaptionEmbeddingTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.CaptionEmbedding
  alias VideoSuggestion.Reco.Vector

  test "embeds a caption into a normalized vector" do
    assert {:ok, vec} = CaptionEmbedding.embed("Cats and dogs")
    assert length(vec) == CaptionEmbedding.dims()

    assert {:ok, norm} = Vector.l2_norm(vec)
    assert_in_delta norm, 1.0, 1.0e-6
  end

  test "is deterministic for identical captions" do
    assert {:ok, v1} = CaptionEmbedding.embed("Cats and dogs")
    assert {:ok, v2} = CaptionEmbedding.embed("Cats and dogs")
    assert v1 == v2
  end

  test "returns :empty for blank captions" do
    assert {:error, :empty} = CaptionEmbedding.embed("")
    assert {:error, :empty} = CaptionEmbedding.embed("   ")
  end
end

