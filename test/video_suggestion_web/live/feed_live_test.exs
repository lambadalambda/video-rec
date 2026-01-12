defmodule VideoSuggestionWeb.FeedLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Videos

  test "feed videos fit within the viewport without native controls", %{conn: conn} do
    user = user_fixture()

    {:ok, _video} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "sample.mp4",
        caption: "hello",
        original_filename: "sample.mp4",
        content_type: "video/mp4"
      })

    {:ok, _lv, html} = live(conn, "/")

    assert html =~ ~s(id="feed")
    assert html =~ "no-scrollbar"
    assert html =~ ~s(phx-hook="VideoFeed")
    assert html =~ "data-feed-prev"
    assert html =~ "data-feed-next"
    assert html =~ "data-feed-item"
    assert html =~ "data-feed-video"
    assert html =~ "object-contain"
    refute html =~ "object-cover"
    refute html =~ ~s( controls)
  end
end
