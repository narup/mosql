defmodule MosqlWeb.PageController do
  use MosqlWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
