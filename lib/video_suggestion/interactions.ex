defmodule VideoSuggestion.Interactions do
  @moduledoc """
  Tracks user interactions with videos for analytics and recommendations.
  """

  alias VideoSuggestion.Interactions.Interaction
  alias VideoSuggestion.Repo

  @spec create_interaction(map()) :: {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def create_interaction(attrs) when is_map(attrs) do
    %Interaction{}
    |> Interaction.changeset(attrs)
    |> Repo.insert()
  end
end
