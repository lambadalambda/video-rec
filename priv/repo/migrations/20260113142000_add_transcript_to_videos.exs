defmodule VideoSuggestion.Repo.Migrations.AddTranscriptToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :transcript, :text
    end
  end
end
