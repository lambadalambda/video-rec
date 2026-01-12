defmodule VideoSuggestion.Reco.RankingTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.Ranking

  describe "rank_by_dot/2" do
    test "orders candidates by descending dot product score" do
      query = [1, 0]

      candidates = [
        %{id: :a, vector: [1, 0]},
        %{id: :b, vector: [0, 1]},
        %{id: :c, vector: [-1, 0]}
      ]

      assert {:ok, ranked} = Ranking.rank_by_dot(query, candidates)

      assert Enum.map(ranked, fn {c, _score} -> c.id end) == [:a, :b, :c]
    end
  end

  describe "mmr/4" do
    test "selects a diverse set when lambda is low" do
      query = [1, 0]

      candidates = [
        %{id: :a, vector: [1, 0]},
        %{id: :b, vector: [0.99, 0.01]},
        %{id: :c, vector: [0, 1]}
      ]

      assert {:ok, selected} = Ranking.mmr(query, candidates, 2, lambda: 0.2)
      assert Enum.map(selected, & &1.id) == [:a, :c]
    end
  end

  describe "filter/2" do
    test "filters seen and blocked creators and enforces per-creator cap" do
      candidates = [
        %{id: 1, creator_id: 10},
        %{id: 2, creator_id: 10},
        %{id: 3, creator_id: 11},
        %{id: 4, creator_id: 12}
      ]

      opts = [
        seen_ids: MapSet.new([3]),
        blocked_creator_ids: MapSet.new([12]),
        max_per_creator: 1
      ]

      assert Ranking.filter(candidates, opts) == [
               %{id: 1, creator_id: 10}
             ]
    end
  end
end
