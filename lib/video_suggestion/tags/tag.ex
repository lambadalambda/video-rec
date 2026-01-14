defmodule VideoSuggestion.Tags.Tag do
  use Ecto.Schema

  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :version, :string
    field :vector, Pgvector.Ecto.Vector

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :version, :vector])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
