defmodule VideoSuggestion.Repo do
  use Ecto.Repo,
    otp_app: :video_suggestion,
    adapter: Ecto.Adapters.Postgres
end
