defmodule VideoSuggestion.InteractionsTest do
  use VideoSuggestion.DataCase, async: true

  alias VideoSuggestion.Interactions
  alias VideoSuggestion.Videos

  import VideoSuggestion.AccountsFixtures

  describe "create_interaction/1" do
    test "creates an impression interaction for a user and video" do
      user = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      assert {:ok, interaction} =
               Interactions.create_interaction(%{
                 user_id: user.id,
                 video_id: video.id,
                 event_type: "impression"
               })

      assert interaction.user_id == user.id
      assert interaction.video_id == video.id
      assert interaction.event_type == "impression"
      assert interaction.watch_ms == nil
    end

    test "validates event_type" do
      user = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      assert {:error, changeset} =
               Interactions.create_interaction(%{
                 user_id: user.id,
                 video_id: video.id,
                 event_type: "nope"
               })

      assert "is invalid" in errors_on(changeset).event_type
    end

    test "requires watch_ms for watch events" do
      user = user_fixture()

      {:ok, video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })

      assert {:error, changeset} =
               Interactions.create_interaction(%{
                 user_id: user.id,
                 video_id: video.id,
                 event_type: "watch"
               })

      assert "can't be blank" in errors_on(changeset).watch_ms
    end
  end
end
