defmodule VideoSuggestionWeb.Admin.RecommendationsLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Videos
  alias VideoSuggestion.Videos.VideoEmbedding

  import VideoSuggestion.AccountsFixtures

  test "admin can access recommendations page", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, _view, html} = live(log_in_user(conn, admin), "/admin/recommendations")
    assert html =~ "Recommendations"
  end

  test "non-admin cannot access recommendations page", %{conn: conn} do
    _admin = user_fixture()
    user = user_fixture()
    refute user.is_admin

    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(conn, user), "/admin/recommendations")
  end

  test "page shows ranked videos for a user with favorites", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    conn = log_in_user(conn, admin)

    {:ok, liked} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "reco-liked",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, good} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "reco-good",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, bad} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "reco-bad",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    set_embedding!(liked.id, [1.0, 0.0])
    set_embedding!(good.id, [0.9, 0.1])
    set_embedding!(bad.id, [-1.0, 0.0])

    assert {:ok, %{favorited: true}} = Videos.toggle_favorite(admin.id, liked.id)

    {:ok, _view, html} = live(conn, "/admin/recommendations")
    assert html =~ "reco-good"
    assert html =~ "reco-bad"

    {good_pos, _} = :binary.match(html, "reco-good")
    {bad_pos, _} = :binary.match(html, "reco-bad")
    assert good_pos < bad_pos
  end

  defp set_embedding!(video_id, vector) when is_integer(video_id) and is_list(vector) do
    embedding = Videos.get_video_embedding!(video_id)

    {:ok, _} =
      embedding
      |> VideoEmbedding.changeset(%{vector: vector, version: "test"})
      |> Repo.update()

    :ok
  end
end
