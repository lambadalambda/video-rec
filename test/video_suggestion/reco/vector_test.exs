defmodule VideoSuggestion.Reco.VectorTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.Vector

  describe "dot/2" do
    test "computes dot product for same-dimension vectors" do
      assert {:ok, 32.0} = Vector.dot([1, 2, 3], [4, 5, 6])
    end

    test "errors on dimension mismatch" do
      assert {:error, :dimension_mismatch} = Vector.dot([1, 2], [1, 2, 3])
    end

    test "errors on empty vectors" do
      assert {:error, :empty_vector} = Vector.dot([], [])
    end
  end

  describe "l2_norm/1" do
    test "computes L2 norm" do
      assert {:ok, norm} = Vector.l2_norm([3, 4])
      assert_in_delta norm, 5.0, 1.0e-12
    end

    test "errors on empty vector" do
      assert {:error, :empty_vector} = Vector.l2_norm([])
    end
  end

  describe "normalize/1" do
    test "normalizes a vector to unit length" do
      assert {:ok, v} = Vector.normalize([3, 4])
      assert {:ok, norm} = Vector.l2_norm(v)
      assert_in_delta norm, 1.0, 1.0e-12
    end

    test "errors on zero vector" do
      assert {:error, :zero_norm} = Vector.normalize([0, 0, 0])
    end
  end

  describe "mean/1" do
    test "computes element-wise mean of vectors" do
      assert {:ok, [2.0, 3.0]} = Vector.mean([[1, 2], [3, 4]])
    end

    test "errors on empty list" do
      assert {:error, :empty} = Vector.mean([])
    end

    test "errors on dimension mismatch" do
      assert {:error, :dimension_mismatch} = Vector.mean([[1, 2], [1, 2, 3]])
    end
  end
end
