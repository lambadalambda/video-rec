defmodule VideoSuggestion.Reco.TaggingTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.Tagging

  describe "top_k/3" do
    test "scores tags by dot product and returns top K" do
      video = [1, 0]

      tags = [
        %{id: :cats, vector: [1, 0]},
        %{id: :dogs, vector: [0, 1]}
      ]

      assert {:ok, [{tag, score}]} = Tagging.top_k(video, tags, 1)
      assert tag.id == :cats
      assert_in_delta score, 1.0, 1.0e-12
    end

    test "breaks ties deterministically by tag id" do
      video = [1, 0]

      tags = [
        %{id: :a, vector: [1, 0]},
        %{id: :b, vector: [1, 0]}
      ]

      assert {:ok, [{tag1, 1.0}, {tag2, 1.0}]} = Tagging.top_k(video, tags, 2)
      assert {tag1.id, tag2.id} == {:a, :b}
    end
  end
end
