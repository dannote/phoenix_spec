defmodule TestAppWeb.PostController do
  def init(opts), do: opts
  def call(conn, _opts), do: conn
end

defmodule TestAppWeb.UserController do
  def init(opts), do: opts
  def call(conn, _opts), do: conn
end

defmodule TestAppWeb.CommentController do
  def init(opts), do: opts
  def call(conn, _opts), do: conn
end

defmodule TestAppWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TestAppWeb do
    pipe_through :api

    resources "/posts", PostController, only: [:index, :show, :create]
    resources "/users", UserController, only: [:index, :show]

    resources "/posts/:post_id/comments", CommentController, only: [:index, :show]
  end
end
