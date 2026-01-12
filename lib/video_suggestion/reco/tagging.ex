defmodule VideoSuggestion.Reco.Tagging do
  @moduledoc """
  Auto-tagging helpers (taxonomy scoring).
  """

  alias VideoSuggestion.Reco.Vector

  @type tag :: %{required(:id) => any(), required(:vector) => Vector.t()}

  @spec top_k(Vector.t(), [tag()], non_neg_integer()) ::
          {:ok, [{tag(), float()}]} | {:error, :invalid_k | :empty_vector | :dimension_mismatch}
  def top_k(_video, _tags, k) when not (is_integer(k) and k >= 0), do: {:error, :invalid_k}

  def top_k(video, tags, k) when is_list(tags) do
    tags
    |> Enum.reduce_while({:ok, []}, fn tag, {:ok, acc} ->
      case Vector.dot(video, tag.vector) do
        {:ok, score} -> {:cont, {:ok, [{tag, score} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, scored} ->
        {:ok,
         scored
         |> Enum.sort_by(fn {tag, score} -> {-score, to_string(tag.id)} end)
         |> Enum.take(k)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
