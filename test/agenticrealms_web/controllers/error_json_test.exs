defmodule AgenticRealmsWeb.ErrorJSONTest do
  use AgenticRealmsWeb.ConnCase, async: true

  test "renders 404" do
    assert AgenticRealmsWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert AgenticRealmsWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
