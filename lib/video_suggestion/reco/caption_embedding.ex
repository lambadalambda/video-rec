defmodule VideoSuggestion.Reco.CaptionEmbedding do
  @moduledoc """
  Dependency-free, deterministic caption embedding for MVP ranking.

  This is a placeholder until real multimodal embeddings are wired in.
  """

  alias VideoSuggestion.Reco.Vector

  @default_dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  @spec dims() :: pos_integer()
  def dims, do: @default_dims

  @spec embed(String.t(), keyword()) ::
          {:ok, Vector.t()} | {:error, :empty | :invalid_dims | :zero_norm}
  def embed(caption, opts \\ []) when is_binary(caption) do
    dims = Keyword.get(opts, :dims, @default_dims)

    cond do
      not (is_integer(dims) and dims > 0) ->
        {:error, :invalid_dims}

      String.trim(caption) == "" ->
        {:error, :empty}

      true ->
        tokens =
          caption
          |> String.downcase()
          |> String.trim()
          |> String.split(~r/[^a-z0-9]+/u, trim: true)

        if tokens == [] do
          {:error, :empty}
        else
          counts =
            Enum.reduce(tokens, %{}, fn token, acc ->
              idx = :erlang.phash2(token, dims)
              sign = if :erlang.phash2({token, :sign}, 2) == 0, do: 1.0, else: -1.0
              Map.update(acc, idx, sign, &(&1 + sign))
            end)

          vec = for i <- 0..(dims - 1), do: Map.get(counts, i, 0.0)

          case Vector.normalize(vec) do
            {:ok, v} -> {:ok, v}
            {:error, :zero_norm} -> {:error, :zero_norm}
            {:error, :empty_vector} -> {:error, :empty}
          end
        end
    end
  end
end
