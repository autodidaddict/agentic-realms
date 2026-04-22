defmodule AgenticRealmsWeb.PageController do
  use AgenticRealmsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
