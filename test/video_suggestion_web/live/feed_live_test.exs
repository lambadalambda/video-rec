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
    assert html =~ "data-feed-sound-toggle"
    assert html =~ "data-feed-item"
    assert html =~ "data-feed-video"
    assert html =~ "object-contain"
    refute html =~ "object-cover"
    refute html =~ ~s( controls)
  end

  test "signed-in user can favorite and unfavorite a video", %{conn: conn} do
    user = user_fixture()

    {:ok, video} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "hello",
        original_filename: "sample.mp4",
        content_type: "video/mp4"
      })

    {:ok, lv, _html} = live(log_in_user(conn, user), "/")

    assert lv
           |> element(~s([data-favorites-count][data-video-id="#{video.id}"]))
           |> render() =~ ~r/>\s*0\s*</

    lv
    |> element(~s([data-favorite-button][data-video-id="#{video.id}"]))
    |> render_click()

    assert Videos.favorites_count(video.id) == 1

    assert lv
           |> element(~s([data-favorites-count][data-video-id="#{video.id}"]))
           |> render() =~ ~r/>\s*1\s*</

    lv
    |> element(~s([data-favorite-button][data-video-id="#{video.id}"]))
    |> render_click()

    assert Videos.favorites_count(video.id) == 0
  end

  test "feed wraps by rendering clone items when there are multiple videos", %{conn: conn} do
    user = user_fixture()

    {:ok, _video_1} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "first",
        original_filename: "sample.mp4",
        content_type: "video/mp4"
      })

    {:ok, _video_2} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "second",
        original_filename: "sample.mp4",
        content_type: "video/mp4"
      })

    {:ok, _lv, html} = live(conn, "/")

    assert html =~ ~s(data-feed-clone="prev")
    assert html =~ ~s(data-feed-clone="next")
  end
end
