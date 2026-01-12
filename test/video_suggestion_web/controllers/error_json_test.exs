defmodule VideoSuggestionWeb.ErrorJSONTest do
  use VideoSuggestionWeb.ConnCase, async: true

  test "renders 404" do
    assert VideoSuggestionWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert VideoSuggestionWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
