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

  describe "evidence_gamma/2 and blended_vector/1" do
    test "errors on empty profiles" do
      assert {:error, :empty} = TasteProfile.evidence_gamma(TasteProfile.new())
      assert {:error, :empty} = TasteProfile.blended_vector(TasteProfile.new())
    end

    test "uses a prior so the first session signal does not dominate" do
      profile =
        TasteProfile.new()
        |> TasteProfile.update_session!([1, 0], 1.0)

      assert {:ok, gamma} = TasteProfile.evidence_gamma(profile, prior: 3.0)
      assert_in_delta gamma, 0.25, 1.0e-12
    end

    test "computes an evidence-weighted gamma and uses it for blending" do
      profile =
        TasteProfile.new()
        |> TasteProfile.update_long!([1, 0])
        |> TasteProfile.update_long!([1, 0])
        |> TasteProfile.update_session!([0, 1], 1.0)

      assert {:ok, gamma} = TasteProfile.evidence_gamma(profile, prior: 3.0)
      assert_in_delta gamma, 1.0 / 6.0, 1.0e-12
      assert TasteProfile.blended_vector(profile) == TasteProfile.blended_vector(profile, gamma)
    end
  end
end
