defmodule VideoSuggestion.Reco.TasteProfile do
  @moduledoc """
  Long-term and session taste vectors for a user.
  """

  alias VideoSuggestion.Reco.Vector

  defstruct long_sum: nil,
            long_weight: 0.0,
            session: nil

  @type t :: %__MODULE__{
          long_sum: [float()] | nil,
          long_weight: float(),
          session: [float()] | nil
        }

  def new, do: %__MODULE__{}

  def update_long!(%__MODULE__{} = profile, vector, weight \\ 1.0) do
    case update_long(profile, vector, weight) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "update_long failed: #{inspect(reason)}"
    end
  end

  @spec update_long(t(), Vector.t(), number()) ::
          {:ok, t()} | {:error, :empty_vector | :dimension_mismatch | :invalid_weight}
  def update_long(%__MODULE__{} = profile, vector, weight \\ 1.0) when is_list(vector) do
    cond do
      not (is_number(weight) and weight > 0) ->
        {:error, :invalid_weight}

      vector == [] ->
        {:error, :empty_vector}

      is_nil(profile.long_sum) ->
        {:ok,
         %{
           profile
           | long_sum: Enum.map(vector, &(&1 * weight)),
             long_weight: weight * 1.0
         }}

      length(profile.long_sum) != length(vector) ->
        {:error, :dimension_mismatch}

      true ->
        new_sum = Enum.zip_with(profile.long_sum, vector, fn s, x -> s + x * weight end)

        {:ok,
         %{
           profile
           | long_sum: new_sum,
             long_weight: profile.long_weight + weight
         }}
    end
  end

  @spec long_vector(t()) :: {:ok, [float()]} | {:error, :empty | :empty_vector | :zero_norm}
  def long_vector(%__MODULE__{long_sum: nil}), do: {:error, :empty}

  def long_vector(%__MODULE__{long_sum: sum}) do
    Vector.normalize(sum)
  end

  def update_session!(%__MODULE__{} = profile, vector, alpha \\ 0.2) do
    case update_session(profile, vector, alpha) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "update_session failed: #{inspect(reason)}"
    end
  end

  @spec update_session(t(), Vector.t(), number()) ::
          {:ok, t()}
          | {:error, :empty_vector | :dimension_mismatch | :invalid_alpha | :zero_norm}
  def update_session(%__MODULE__{} = profile, vector, alpha \\ 0.2) when is_list(vector) do
    cond do
      not (is_number(alpha) and alpha >= 0 and alpha <= 1) ->
        {:error, :invalid_alpha}

      vector == [] ->
        {:error, :empty_vector}

      is_nil(profile.session) ->
        with {:ok, v} <- Vector.normalize(vector) do
          {:ok, %{profile | session: v}}
        end

      length(profile.session) != length(vector) ->
        {:error, :dimension_mismatch}

      true ->
        with {:ok, v} <- Vector.normalize(vector) do
          blended =
            Enum.zip_with(profile.session, v, fn old, new ->
              (1 - alpha) * old + alpha * new
            end)

          with {:ok, session} <- Vector.normalize(blended) do
            {:ok, %{profile | session: session}}
          end
        end
    end
  end

  @spec session_vector(t()) :: {:ok, [float()]} | {:error, :empty}
  def session_vector(%__MODULE__{session: nil}), do: {:error, :empty}
  def session_vector(%__MODULE__{session: session}), do: {:ok, session}

  @spec blended_vector(t(), number()) ::
          {:ok, [float()]}
          | {:error, :empty | :invalid_gamma | :empty_vector | :dimension_mismatch | :zero_norm}
  def blended_vector(%__MODULE__{} = profile, gamma) do
    cond do
      not (is_number(gamma) and gamma >= 0 and gamma <= 1) ->
        {:error, :invalid_gamma}

      true ->
        long =
          case long_vector(profile) do
            {:ok, v} -> v
            {:error, :empty} -> nil
            {:error, reason} -> {:error, reason}
          end

        session =
          case session_vector(profile) do
            {:ok, v} -> v
            {:error, :empty} -> nil
          end

        case {long, session} do
          {{:error, reason}, _} ->
            {:error, reason}

          {nil, nil} ->
            {:error, :empty}

          {long, nil} when is_list(long) ->
            {:ok, long}

          {nil, session} when is_list(session) ->
            {:ok, session}

          {long, session} ->
            if length(long) != length(session) do
              {:error, :dimension_mismatch}
            else
              blended =
                Enum.zip_with(long, session, fn l, s ->
                  (1 - gamma) * l + gamma * s
                end)

              Vector.normalize(blended)
            end
        end
    end
  end
end
