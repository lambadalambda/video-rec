defmodule VideoSuggestionWeb.Admin.VideoSimilarityLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias VideoSuggestion.Videos

  import VideoSuggestion.AccountsFixtures

  test "admin can access video similarity pages", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, _view, html} = live(log_in_user(conn, admin), "/admin/similarity")
    assert html =~ "Video similarity"
  end

  test "non-admin cannot access video similarity pages", %{conn: conn} do
    _admin = user_fixture()
    user = user_fixture()
    refute user.is_admin

    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(conn, user), "/admin/similarity")
  end

  test "page shows the most similar videos ranked by similarity", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    conn = log_in_user(conn, admin)

    {:ok, query} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "sim-query",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, good} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "sim-good",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, bad} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "sim-bad",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(query.id, "test", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(good.id, "test", [0.9, 0.1])
    {:ok, _} = Videos.upsert_video_embedding(bad.id, "test", [-1.0, 0.0])

    {:ok, _view, html} = live(conn, "/admin/similarity/#{query.id}")
    assert html =~ "sim-query"
    assert html =~ "sim-good"
    assert html =~ "sim-bad"

    {good_pos, _} = :binary.match(html, "sim-good")
    {bad_pos, _} = :binary.match(html, "sim-bad")
    assert good_pos < bad_pos
  end
end
