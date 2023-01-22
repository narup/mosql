defmodule MosqlWebWeb.PageController do
  use MosqlWebWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
