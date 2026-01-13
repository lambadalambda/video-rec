defmodule VideoSuggestion.Interactions.Interaction do
  use Ecto.Schema

  import Ecto.Changeset

  @event_types ~w(impression watch favorite unfavorite)

  schema "interactions" do
    field :event_type, :string
    field :watch_ms, :integer

    belongs_to :user, VideoSuggestion.Accounts.User
    belongs_to :video, VideoSuggestion.Videos.Video

    timestamps(type: :utc_datetime)
  end

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [:user_id, :video_id, :event_type, :watch_ms])
    |> validate_required([:user_id, :video_id, :event_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_number(:watch_ms, greater_than_or_equal_to: 0)
    |> validate_watch_ms()
    |> assoc_constraint(:user)
    |> assoc_constraint(:video)
  end

  def event_types, do: @event_types

  defp validate_watch_ms(changeset) do
    case get_field(changeset, :event_type) do
      "watch" -> validate_required(changeset, [:watch_ms])
      _ -> changeset
    end
  end
end
