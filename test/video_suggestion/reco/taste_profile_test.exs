defmodule VideoSuggestion.Reco.TasteProfileTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.TasteProfile

  describe "update_long/3 and long_vector/1" do
    test "builds a long-term taste vector from weighted positives" do
      profile =
        TasteProfile.new()
        |> TasteProfile.update_long!([1, 0])
        |> TasteProfile.update_long!([0, 1])

      assert {:ok, [x, y]} = TasteProfile.long_vector(profile)
      assert_in_delta x, :math.sqrt(2) / 2, 1.0e-12
      assert_in_delta y, :math.sqrt(2) / 2, 1.0e-12
    end
  end

  describe "update_session/3 and session_vector/1" do
    test "updates a session vector via EMA and normalizes" do
      profile =
        TasteProfile.new()
        |> TasteProfile.update_session!([1, 0], 0.5)
        |> TasteProfile.update_session!([0, 1], 0.5)

      assert {:ok, [x, y]} = TasteProfile.session_vector(profile)
      assert_in_delta x, :math.sqrt(2) / 2, 1.0e-12
      assert_in_delta y, :math.sqrt(2) / 2, 1.0e-12
    end
  end

  describe "blended_vector/2" do
    test "blends long-term and session vectors" do
      profile =
        TasteProfile.new()
        |> TasteProfile.update_long!([1, 0])
        |> TasteProfile.update_session!([0, 1], 1.0)

      assert {:ok, [x, y]} = TasteProfile.blended_vector(profile, 0.5)
      assert_in_delta x, :math.sqrt(2) / 2, 1.0e-12
      assert_in_delta y, :math.sqrt(2) / 2, 1.0e-12
    end
  end
end
