defmodule VideoSuggestionWeb.Admin.VideoUploadLiveTest do
  use VideoSuggestionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import VideoSuggestion.AccountsFixtures
  alias VideoSuggestion.Uploads
  alias VideoSuggestion.Videos

  test "admin can access the upload page", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, _view, html} = live(log_in_user(conn, admin), "/admin/videos/new")
    assert html =~ "Upload video"
    assert html =~ ~s(enctype="multipart/form-data")
    assert html =~ ~s(phx-change="validate")
    assert html =~ "data-phx-auto-upload"
  end

  test "non-admin cannot access the upload page", %{conn: conn} do
    _admin = user_fixture()
    user = user_fixture()
    refute user.is_admin

    assert {:error, {:redirect, %{to: "/"}}} = live(log_in_user(conn, user), "/admin/videos/new")
  end

  test "admin can upload a video and it appears in the feed", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, lv, _html} = live(log_in_user(conn, admin), "/admin/videos/new")

    upload =
      file_input(lv, "#video_upload_form", :video, [
        %{name: "sample.mp4", content: "not-a-real-mp4", type: "video/mp4"}
      ])

    render_upload(upload, "sample.mp4")

    lv
    |> form("#video_upload_form", video: %{"caption" => "hello"})
    |> render_submit()

    assert_redirect(lv, "/")

    [video] = Videos.list_videos(limit: 1)
    on_exit(fn -> File.rm_rf(Uploads.path(video.storage_key)) end)

    assert video.caption == "hello"
    assert File.exists?(Uploads.path(video.storage_key))

    {:ok, _feed, feed_html} = live(conn, "/")
    assert feed_html =~ Uploads.url(video.storage_key)
  end

  test "admin gets a helpful message if submitting before upload completes", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, lv, _html} = live(log_in_user(conn, admin), "/admin/videos/new")

    upload =
      file_input(lv, "#video_upload_form", :video, [
        %{name: "sample.mp4", content: "not-a-real-mp4", type: "video/mp4"}
      ])

    render_upload(upload, "sample.mp4", 50)

    html =
      lv
      |> form("#video_upload_form", video: %{"caption" => "hello"})
      |> render_submit()

    assert html =~ "Upload still in progress"

    render_upload(upload, "sample.mp4", 50)

    lv
    |> form("#video_upload_form", video: %{"caption" => "hello"})
    |> render_submit()

    assert_redirect(lv, "/")

    [video] = Videos.list_videos(limit: 1)
    on_exit(fn -> File.rm_rf(Uploads.path(video.storage_key)) end)
  end

  test "upload shows a helpful error when the file type is not accepted", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    {:ok, lv, _html} = live(log_in_user(conn, admin), "/admin/videos/new")

    upload =
      file_input(lv, "#video_upload_form", :video, [
        %{name: "sample.txt", content: "hello", type: "text/plain"}
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "sample.txt")

    html = render(lv)
    assert html =~ "unacceptable file type"
  end

end
