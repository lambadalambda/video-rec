defmodule VideoSuggestion.Reco.DeterministicEmbedding do
  @moduledoc """
  Deterministic embeddings derived from a binary seed.

  Used as a fallback when no meaningful caption embedding can be produced.
  """

  alias VideoSuggestion.Reco.Vector

  @default_dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  @spec dims() :: pos_integer()
  def dims, do: @default_dims

  @spec from_seed(binary(), keyword()) :: [float()]
  def from_seed(seed, opts \\ []) when is_binary(seed) do
    dims = Keyword.get(opts, :dims, @default_dims)

    bytes = expand_bytes(seed, dims)

    vec =
      bytes
      |> :binary.bin_to_list()
      |> Enum.map(fn b -> (b - 127.5) / 127.5 end)

    case Vector.normalize(vec) do
      {:ok, v} -> v
      {:error, _} -> [1.0 | List.duplicate(0.0, dims - 1)]
    end
  end

  defp expand_bytes(seed, dims) do
    chunks = div(dims + 31, 32)

    bytes =
      0..(chunks - 1)
      |> Enum.reduce(<<>>, fn i, acc ->
        acc <> :crypto.hash(:sha256, seed <> <<i::unsigned-32>>)
      end)

    binary_part(bytes, 0, dims)
  end
end
