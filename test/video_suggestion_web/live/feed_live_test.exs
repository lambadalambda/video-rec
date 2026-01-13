defmodule VideoSuggestionWeb.FeedLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import VideoSuggestion.AccountsFixtures

  alias VideoSuggestion.Interactions.Interaction
  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos

  test "feed videos fit within the viewport without native controls", %{conn: conn} do
    user = user_fixture()

    {:ok, _video} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "sample.mp4",
        caption: "hello",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _lv, html} = live(conn, "/")

    assert html =~ ~s(id="feed")
    assert html =~ "no-scrollbar"
    assert html =~ ~s(phx-hook="VideoFeed")
    assert html =~ "data-feed-prev"
    assert html =~ "data-feed-next"
    assert html =~ "data-feed-play-toggle"
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
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, lv, _html} = live(log_in_user(conn, user), "/")

    assert Repo.aggregate(Interaction, :count, :id) == 0

    assert lv
           |> element(~s([data-favorites-count][data-video-id="#{video.id}"]))
           |> render() =~ ~r/>\s*0\s*</

    lv
    |> element(~s([data-favorite-button][data-video-id="#{video.id}"]))
    |> render_click()

    assert Videos.favorites_count(video.id) == 1
    assert Repo.aggregate(Interaction, :count, :id) == 1

    assert lv
           |> element(~s([data-favorites-count][data-video-id="#{video.id}"]))
           |> render() =~ ~r/>\s*1\s*</

    lv
    |> element(~s([data-favorite-button][data-video-id="#{video.id}"]))
    |> render_click()

    assert Videos.favorites_count(video.id) == 0
    assert Repo.aggregate(Interaction, :count, :id) == 2

    assert Interaction |> Repo.all() |> Enum.map(& &1.event_type) |> Enum.sort() == [
             "favorite",
             "unfavorite"
           ]
  end

  test "feed wraps by rendering clone items when there are multiple videos", %{conn: conn} do
    user = user_fixture()

    {:ok, _video_1} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "first",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _video_2} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "second",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _lv, html} = live(conn, "/")

    assert html =~ ~s(data-feed-clone="prev")
    assert html =~ ~s(data-feed-clone="next")
  end

  test "feed loads more videos on demand", %{conn: conn} do
    user = user_fixture()

    {:ok, _oldest} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "oldest",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    Enum.each(1..50, fn _ ->
      {:ok, _video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          caption: "new",
          original_filename: "sample.mp4",
          content_type: "video/mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })
    end)

    {:ok, lv, html} = live(conn, "/")
    assert html =~ ~s(data-feed-has-more="true")
    refute html =~ ~s(data-feed-clone="prev")
    refute html =~ ~s(data-feed-clone="next")
    refute html =~ "oldest"

    html = render_hook(lv, "load-more", %{})

    assert html =~ ~s(data-feed-has-more="false")
    assert html =~ "oldest"
    assert html =~ ~s(data-feed-clone="prev")
    assert html =~ ~s(data-feed-clone="next")
  end

  test "feed can jump to the end to support previous-from-first wrap", %{conn: conn} do
    user = user_fixture()

    {:ok, _oldest} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "oldest",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    Enum.each(1..80, fn i ->
      {:ok, _video} =
        Videos.create_video(%{
          user_id: user.id,
          storage_key: "#{System.unique_integer([:positive])}.mp4",
          caption: "new-#{i}",
          original_filename: "sample.mp4",
          content_type: "video/mp4",
          content_hash: :crypto.strong_rand_bytes(32)
        })
    end)

    {:ok, lv, html} = live(conn, "/")

    assert html =~ ~s(data-feed-has-more="true")
    refute html =~ "oldest"
    assert html =~ "new-80"

    html = render_hook(lv, "jump-to-end", %{})

    assert html =~ ~s(data-feed-has-more="false")
    assert html =~ ~s(data-feed-mode="tail")
    assert html =~ "oldest"
    assert html =~ "new-1"
    refute html =~ "new-80"
    refute html =~ ~s(data-feed-clone="prev")
    refute html =~ ~s(data-feed-clone="next")
  end

  test "feed logs interaction batches for signed-in users", %{conn: conn} do
    user = user_fixture()

    {:ok, video} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "hello",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, lv, _html} = live(log_in_user(conn, user), "/")

    assert Repo.aggregate(Interaction, :count, :id) == 0

    render_hook(lv, "interaction-batch", %{
      "events" => [
        %{"type" => "impression", "video_id" => video.id},
        %{"type" => "watch", "video_id" => video.id, "watch_ms" => 1234}
      ]
    })

    assert Repo.aggregate(Interaction, :count, :id) == 2
  end

  test "feed uses embeddings for ordering when a signed-in user has taste evidence", %{conn: conn} do
    user = user_fixture()

    {:ok, seed} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "seed",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    filler_ids =
      Enum.map(1..51, fn i ->
        {:ok, video} =
          Videos.create_video(%{
            user_id: user.id,
            storage_key: "#{System.unique_integer([:positive])}.mp4",
            caption: "filler-#{i}",
            original_filename: "sample.mp4",
            content_type: "video/mp4",
            content_hash: :crypto.strong_rand_bytes(32)
          })

        video.id
      end)

    {:ok, good} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "good",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, bad} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "bad",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(seed.id, "test", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(good.id, "test", [0.9, 0.1])
    {:ok, _} = Videos.upsert_video_embedding(bad.id, "test", [-1.0, 0.0])

    Enum.each(filler_ids, fn id ->
      {:ok, _} = Videos.upsert_video_embedding(id, "test", [-2.0, 0.0])
    end)

    assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, seed.id)

    {:ok, _lv, html} = live(log_in_user(conn, user), "/")

    {good_pos, _} = :binary.match(html, "good")
    {bad_pos, _} = :binary.match(html, "bad")
    assert good_pos < bad_pos
  end

  test "ranked feed load-more continues ranked ordering and keeps favorites excluded", %{
    conn: conn
  } do
    user = user_fixture()

    {:ok, seed} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "seed",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    filler_ids =
      Enum.map(1..51, fn i ->
        {:ok, video} =
          Videos.create_video(%{
            user_id: user.id,
            storage_key: "#{System.unique_integer([:positive])}.mp4",
            caption: "filler-#{i}",
            original_filename: "sample.mp4",
            content_type: "video/mp4",
            content_hash: :crypto.strong_rand_bytes(32)
          })

        video.id
      end)

    {:ok, good} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "good",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, bad} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "bad",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(seed.id, "test", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(good.id, "test", [0.9, 0.1])
    {:ok, _} = Videos.upsert_video_embedding(bad.id, "test", [-1.0, 0.0])

    Enum.each(filler_ids, fn id ->
      {:ok, _} = Videos.upsert_video_embedding(id, "test", [-2.0, 0.0])
    end)

    assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, seed.id)

    {:ok, lv, html} = live(log_in_user(conn, user), "/")

    assert html =~ ~s(data-feed-has-more="true")
    refute html =~ "seed"

    html = render_hook(lv, "load-more", %{})

    assert html =~ ~s(data-feed-has-more="false")
    assert html =~ ~s(data-feed-clone="prev")
    assert html =~ ~s(data-feed-clone="next")
    refute html =~ "seed"
  end

  test "ranked feed can jump to the end of the ranked ordering", %{conn: conn} do
    user = user_fixture()

    {:ok, seed} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "seed",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    filler_ids =
      Enum.map(1..60, fn i ->
        {:ok, video} =
          Videos.create_video(%{
            user_id: user.id,
            storage_key: "#{System.unique_integer([:positive])}.mp4",
            caption: "filler-#{i}",
            original_filename: "sample.mp4",
            content_type: "video/mp4",
            content_hash: :crypto.strong_rand_bytes(32)
          })

        video.id
      end)

    {:ok, worst} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "worst",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(seed.id, "test", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(worst.id, "test", [-100.0, 0.0])

    Enum.each(filler_ids, fn id ->
      {:ok, _} = Videos.upsert_video_embedding(id, "test", [-2.0, 0.0])
    end)

    assert {:ok, %{favorited: true}} = Videos.toggle_favorite(user.id, seed.id)

    {:ok, lv, _html} = live(log_in_user(conn, user), "/")

    html = render_hook(lv, "jump-to-end", %{})

    assert html =~ ~s(data-feed-mode="tail")
    assert html =~ "worst"
    refute html =~ "seed"
  end

  test "feed ignores interaction batches for anonymous users", %{conn: conn} do
    user = user_fixture()

    {:ok, video} =
      Videos.create_video(%{
        user_id: user.id,
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        caption: "hello",
        original_filename: "sample.mp4",
        content_type: "video/mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, lv, _html} = live(conn, "/")

    assert Repo.aggregate(Interaction, :count, :id) == 0

    render_hook(lv, "interaction-batch", %{
      "events" => [
        %{"type" => "impression", "video_id" => video.id}
      ]
    })

    assert Repo.aggregate(Interaction, :count, :id) == 0
  end
end
