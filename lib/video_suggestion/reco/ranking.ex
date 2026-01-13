defmodule VideoSuggestion.Reco.Ranking do
  @moduledoc """
  Pure recommendation helpers: scoring, filtering, and reranking.
  """

  alias VideoSuggestion.Reco.Vector

  @type candidate :: %{required(:vector) => Vector.t()}

  @spec rank_by_dot(Vector.t(), [candidate()]) ::
          {:ok, [{candidate(), float()}]} | {:error, :empty_vector | :dimension_mismatch}
  def rank_by_dot(query, candidates) when is_list(candidates) do
    candidates
    |> Enum.reduce_while({:ok, []}, fn candidate, {:ok, acc} ->
      case Vector.dot(query, candidate.vector) do
        {:ok, score} -> {:cont, {:ok, [{candidate, score} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, scored} ->
        {:ok, Enum.sort_by(scored, fn {_candidate, score} -> -score end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec mmr(Vector.t(), [candidate()], non_neg_integer(), keyword()) ::
          {:ok, [candidate()]}
          | {:error, :invalid_k | :invalid_lambda | :empty_vector | :dimension_mismatch}
  def mmr(query, candidates, k, opts \\ [])

  def mmr(_query, _candidates, k, _opts) when not (is_integer(k) and k >= 0) do
    {:error, :invalid_k}
  end

  def mmr(query, candidates, k, opts) when is_list(candidates) do
    lambda = Keyword.get(opts, :lambda, 0.7)

    if not (is_number(lambda) and lambda >= 0 and lambda <= 1) do
      {:error, :invalid_lambda}
    else
      do_mmr(query, candidates, k, lambda, [])
    end
  end

  @spec filter([map()], keyword()) :: [map()]
  def filter(candidates, opts \\ []) when is_list(candidates) do
    seen_ids = Keyword.get(opts, :seen_ids, MapSet.new())
    blocked_creator_ids = Keyword.get(opts, :blocked_creator_ids, MapSet.new())
    max_per_creator = Keyword.get(opts, :max_per_creator)

    candidates
    |> Enum.reject(&MapSet.member?(seen_ids, &1.id))
    |> Enum.reject(&MapSet.member?(blocked_creator_ids, &1.creator_id))
    |> maybe_cap_creator(max_per_creator)
  end

  @spec mix_exploration([map()], [map()], non_neg_integer(), keyword()) ::
          {:ok, [map()]} | {:error, :invalid_k | :invalid_ratio}
  def mix_exploration(exploit, explore, k, opts \\ [])

  def mix_exploration(_exploit, _explore, k, _opts) when not (is_integer(k) and k >= 0) do
    {:error, :invalid_k}
  end

  def mix_exploration(exploit, explore, k, opts) when is_list(exploit) and is_list(explore) do
    ratio = Keyword.get(opts, :ratio, 0.2)

    if not (is_number(ratio) and ratio >= 0 and ratio <= 1) do
      {:error, :invalid_ratio}
    else
      explore_every =
        cond do
          ratio == 0 -> :never
          ratio == 1 -> 1
          true -> max(2, round(1.0 / ratio))
        end

      {:ok, do_mix_exploration(exploit, explore, k, explore_every, 1, MapSet.new(), [])}
    end
  end

  defp do_mix_exploration(_exploit, _explore, 0, _every, _slot, _seen, acc_rev),
    do: Enum.reverse(acc_rev)

  defp do_mix_exploration([], [], _k, _every, _slot, _seen, acc_rev),
    do: Enum.reverse(acc_rev)

  defp do_mix_exploration(exploit, explore, k, every, slot, seen, acc_rev) do
    choose_explore = every != :never and rem(slot, every) == 0

    {picked, exploit, explore, seen} =
      if choose_explore do
        case take_unique(explore, seen) do
          {nil, explore, seen} ->
            case take_unique(exploit, seen) do
              {nil, exploit, seen} -> {nil, exploit, explore, seen}
              {picked, exploit, seen} -> {picked, exploit, explore, seen}
            end

          {picked, explore, seen} ->
            {picked, exploit, explore, seen}
        end
      else
        case take_unique(exploit, seen) do
          {nil, exploit, seen} ->
            case take_unique(explore, seen) do
              {nil, explore, seen} -> {nil, exploit, explore, seen}
              {picked, explore, seen} -> {picked, exploit, explore, seen}
            end

          {picked, exploit, seen} ->
            {picked, exploit, explore, seen}
        end
      end

    if is_nil(picked) do
      Enum.reverse(acc_rev)
    else
      do_mix_exploration(exploit, explore, k - 1, every, slot + 1, seen, [picked | acc_rev])
    end
  end

  defp take_unique([], seen), do: {nil, [], seen}

  defp take_unique([candidate | rest], seen) do
    key = Map.get(candidate, :id) || candidate

    if MapSet.member?(seen, key) do
      take_unique(rest, seen)
    else
      {candidate, rest, MapSet.put(seen, key)}
    end
  end

  defp maybe_cap_creator(candidates, nil), do: candidates

  defp maybe_cap_creator(candidates, max_per_creator)
       when is_integer(max_per_creator) and max_per_creator > 0 do
    {kept_rev, _counts} =
      Enum.reduce(candidates, {[], %{}}, fn candidate, {acc, counts} ->
        creator_id = Map.get(candidate, :creator_id)

        if is_nil(creator_id) do
          {[candidate | acc], counts}
        else
          count = Map.get(counts, creator_id, 0)

          if count < max_per_creator do
            {[candidate | acc], Map.put(counts, creator_id, count + 1)}
          else
            {acc, counts}
          end
        end
      end)

    Enum.reverse(kept_rev)
  end

  defp maybe_cap_creator(candidates, _), do: candidates

  defp do_mmr(_query, _candidates, 0, _lambda, selected_rev),
    do: {:ok, Enum.reverse(selected_rev)}

  defp do_mmr(_query, [], _k, _lambda, selected_rev), do: {:ok, Enum.reverse(selected_rev)}

  defp do_mmr(query, candidates, k, lambda, selected_rev) do
    case best_mmr_candidate(query, candidates, selected_rev, lambda) do
      {:ok, best_candidate} ->
        remaining = List.delete(candidates, best_candidate)
        do_mmr(query, remaining, k - 1, lambda, [best_candidate | selected_rev])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp best_mmr_candidate(query, candidates, selected_rev, lambda) do
    candidates
    |> Enum.reduce_while({:ok, nil, -1.0e308}, fn candidate, {:ok, best_candidate, best_score} ->
      with {:ok, relevance} <- Vector.dot(query, candidate.vector),
           {:ok, diversity} <- max_similarity(candidate.vector, selected_rev) do
        score = lambda * relevance - (1 - lambda) * diversity

        if score > best_score do
          {:cont, {:ok, candidate, score}}
        else
          {:cont, {:ok, best_candidate, best_score}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, nil, _score} -> {:ok, nil}
      {:ok, best_candidate, _score} -> {:ok, best_candidate}
      {:error, reason} -> {:error, reason}
    end
  end

  defp max_similarity(_vector, []), do: {:ok, 0.0}

  defp max_similarity(vector, selected_rev) do
    selected_rev
    |> Enum.reduce_while({:ok, -1.0e308}, fn selected, {:ok, best} ->
      case Vector.dot(vector, selected.vector) do
        {:ok, score} -> {:cont, {:ok, max(best, score)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
