defmodule ReqIsLoveWeb.PageController do
  use ReqIsLoveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
