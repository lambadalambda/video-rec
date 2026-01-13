defmodule VideoSuggestion.Reco.VectorTest do
  use ExUnit.Case, async: true

  alias VideoSuggestion.Reco.Vector

  defp random_vector(dim) when is_integer(dim) and dim > 0 do
    Enum.map(1..dim, fn _ -> :rand.uniform(201) - 101 end)
  end

  defp random_non_zero_vector(dim) when is_integer(dim) and dim > 0 do
    v = random_vector(dim)

    if Enum.all?(v, &(&1 == 0)) do
      [1 | tl(v)]
    else
      v
    end
  end

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

  describe "invariants" do
    test "dot/2 is commutative (within floating error)" do
      :rand.seed(:exsplus, {101, 102, 103})

      Enum.each(1..200, fn _ ->
        a = random_vector(16)
        b = random_vector(16)

        assert {:ok, ab} = Vector.dot(a, b)
        assert {:ok, ba} = Vector.dot(b, a)
        assert_in_delta ab, ba, 1.0e-12
      end)
    end

    test "normalize/1 returns a unit vector (when possible)" do
      :rand.seed(:exsplus, {201, 202, 203})

      Enum.each(1..200, fn _ ->
        v = random_non_zero_vector(32)

        assert {:ok, unit} = Vector.normalize(v)
        assert {:ok, norm} = Vector.l2_norm(unit)
        assert_in_delta norm, 1.0, 1.0e-10
      end)
    end

    test "mean/1 of identical vectors is the same vector" do
      v = [1, -2, 3]
      assert {:ok, [1.0, -2.0, 3.0]} = Vector.mean([v, v, v])
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
