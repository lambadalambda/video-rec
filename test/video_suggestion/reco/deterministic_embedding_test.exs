defmodule VideoSuggestion.Reco.DeterministicEmbeddingTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.DeterministicEmbedding
  alias VideoSuggestion.Reco.Vector

  test "seed embeddings are deterministic and normalized" do
    seed = :crypto.hash(:sha256, "hello")

    v1 = DeterministicEmbedding.from_seed(seed)
    v2 = DeterministicEmbedding.from_seed(seed)

    assert v1 == v2
    assert length(v1) == DeterministicEmbedding.dims()

    assert {:ok, norm} = Vector.l2_norm(v1)
    assert_in_delta norm, 1.0, 1.0e-6
  end
end
