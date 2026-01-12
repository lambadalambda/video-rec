defmodule VideoSuggestion.Reco.Vector do
  @moduledoc """
  Small, dependency-free vector utilities for recommendation logic.
  """

  @type t :: [number()]

  @spec dot(t(), t()) :: {:ok, float()} | {:error, :empty_vector | :dimension_mismatch}
  def dot(a, b) when is_list(a) and is_list(b) do
    cond do
      a == [] or b == [] ->
        {:error, :empty_vector}

      length(a) != length(b) ->
        {:error, :dimension_mismatch}

      true ->
        sum =
          Enum.zip_with(a, b, fn x, y -> x * y end)
          |> Enum.reduce(0.0, fn xy, acc -> acc + xy end)

        {:ok, sum}
    end
  end

  @spec l2_norm(t()) :: {:ok, float()} | {:error, :empty_vector}
  def l2_norm(v) when is_list(v) do
    case dot(v, v) do
      {:ok, sum_sq} -> {:ok, :math.sqrt(sum_sq)}
      {:error, :dimension_mismatch} -> {:error, :empty_vector}
      {:error, :empty_vector} -> {:error, :empty_vector}
    end
  end

  @spec normalize(t()) :: {:ok, [float()]} | {:error, :empty_vector | :zero_norm}
  def normalize(v) when is_list(v) do
    with {:ok, norm} <- l2_norm(v) do
      if norm == 0.0 do
        {:error, :zero_norm}
      else
        {:ok, Enum.map(v, &(&1 / norm))}
      end
    end
  end

  @spec mean([t()]) :: {:ok, [float()]} | {:error, :empty | :empty_vector | :dimension_mismatch}
  def mean([]), do: {:error, :empty}

  def mean(vectors) when is_list(vectors) do
    case vectors do
      [[] | _] ->
        {:error, :empty_vector}

      [first | rest] ->
        dim = length(first)

        cond do
          dim == 0 ->
            {:error, :empty_vector}

          Enum.any?(rest, &(length(&1) != dim)) ->
            {:error, :dimension_mismatch}

          true ->
            sums =
              Enum.reduce(vectors, List.duplicate(0.0, dim), fn v, acc ->
                Enum.zip_with(acc, v, fn a, x -> a + x end)
              end)

            n = length(vectors) * 1.0
            {:ok, Enum.map(sums, &(&1 / n))}
        end
    end
  end
end
