defmodule VideoSuggestionWeb.Admin.VideoSearchLiveTest do
  use VideoSuggestionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VideoSuggestion.Videos

  import VideoSuggestion.AccountsFixtures

  setup do
    stub_name = __MODULE__

    Req.Test.stub(stub_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/embed/text"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          if payload["text"] == "cats" do
            Req.Test.json(conn, %{version: "qwen3_vl_v1", dims: 2, embedding: [1.0, 0.0]})
          else
            Plug.Conn.send_resp(conn, 400, "unexpected query")
          end

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)

    Application.put_env(:video_suggestion, :embedding_worker_req_options,
      plug: {Req.Test, stub_name},
      base_url: "http://embedding-worker"
    )

    on_exit(fn ->
      Application.delete_env(:video_suggestion, :embedding_worker_req_options)
    end)

    :ok
  end

  test "admin can search videos by text and see similar videos ranked", %{conn: conn} do
    admin = user_fixture()
    assert admin.is_admin

    conn = log_in_user(conn, admin)

    {:ok, good} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "good",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, bad} =
      Videos.create_video(%{
        user_id: admin.id,
        caption: "bad",
        storage_key: "#{System.unique_integer([:positive])}.mp4",
        content_hash: :crypto.strong_rand_bytes(32)
      })

    {:ok, _} = Videos.upsert_video_embedding(good.id, "qwen3_vl_v1", [1.0, 0.0])
    {:ok, _} = Videos.upsert_video_embedding(bad.id, "qwen3_vl_v1", [-1.0, 0.0])

    {:ok, lv, _html} = live(conn, "/admin/search")

    html =
      lv
      |> form("#video_search_form", %{"q" => "cats"})
      |> render_submit()

    assert html =~ "qwen3_vl_v1"
    assert html =~ "good"
    assert html =~ "bad"

    {good_pos, _} = :binary.match(html, "good")
    {bad_pos, _} = :binary.match(html, "bad")
    assert good_pos < bad_pos
  end
end
