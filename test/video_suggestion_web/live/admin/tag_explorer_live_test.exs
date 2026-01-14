defmodule VideoSuggestionWeb.Admin.TagExplorerLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias VideoSuggestion.Repo
  alias VideoSuggestion.Tags
  alias VideoSuggestion.Tags.Tag
  alias VideoSuggestion.Videos

  import VideoSuggestion.AccountsFixtures

  @dims Application.compile_env(:video_suggestion, :embedding_dims, 1536)

  test "admin can access tag explorer pages", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, _view, html} = live(log_in_user(conn, admin), "/admin/tags")
    assert html =~ "Tags"
  end

  test "non-admin cannot access tag explorer pages", %{conn: conn} do
    _admin = user_fixture()
    user = user_fixture()
    refute user.is_admin

    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(conn, user), "/admin/tags")
  end

  test "page lists tags by frequency and clicking shows matching videos", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, v1} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "tag-v1",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v2} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "tag-v2",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, v3} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "tag-v3",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(v1.id, "qwen3_vl_v1", pad_vec([1.0, 0.0]))
    {:ok, _} = Videos.upsert_video_embedding(v2.id, "qwen3_vl_v1", pad_vec([0.8, 0.2]))
    {:ok, _} = Videos.upsert_video_embedding(v3.id, "qwen3_vl_v1", pad_vec([0.0, 1.0]))

    Repo.insert!(%Tag{name: "cats", version: "qwen3_vl_v1", vector: pad_vec([1.0, 0.0])})
    Repo.insert!(%Tag{name: "dogs", version: "qwen3_vl_v1", vector: pad_vec([0.0, 1.0])})

    assert {:ok, %{updated_videos: 3}} = Tags.refresh_video_tag_suggestions(top_k: 1)

    conn = log_in_user(conn, admin)

    {:ok, _lv, html} = live(conn, "/admin/tags")
    assert html =~ "cats"
    assert html =~ "dogs"
    assert html =~ "2"
    assert html =~ "1"

    {cats_pos, _} = :binary.match(html, "cats")
    {dogs_pos, _} = :binary.match(html, "dogs")
    assert cats_pos < dogs_pos

    cats = Repo.get_by!(Tag, name: "cats")
    {:ok, _lv, html} = live(conn, "/admin/tags/#{cats.id}")
    assert html =~ "cats"
    assert html =~ "tag-v1"
    assert html =~ "tag-v2"

    {v1_pos, _} = :binary.match(html, "tag-v1")
    {v2_pos, _} = :binary.match(html, "tag-v2")
    assert v1_pos < v2_pos
  end

  defp pad_vec(values) when is_list(values) do
    values ++ List.duplicate(0.0, max(@dims - length(values), 0))
  end
end
