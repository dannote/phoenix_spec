defmodule TestAppWeb.PostController do
  alias TestApp.Post

  def init(opts), do: opts
  def call(conn, _opts), do: conn

  def create(conn, %{"post" => post_params}) do
    _changeset =
      %Post{}
      |> Ecto.Changeset.cast(post_params, [:title, :body, :published])

    conn
    |> Plug.Conn.put_status(:created)
    |> Phoenix.Controller.render(:show, post: %Post{})
  end

  def update(conn, %{"id" => _id, "post" => post_params}) do
    _changeset =
      %Post{}
      |> Ecto.Changeset.cast(post_params, [:title, :body])

    Phoenix.Controller.render(conn, :show, post: %Post{})
  end

  def delete(conn, %{"id" => _id}) do
    Plug.Conn.send_resp(conn, :no_content, "")
  end
end

defmodule TestAppWeb.UserController do
  def init(opts), do: opts
  def call(conn, _opts), do: conn
end

defmodule TestAppWeb.CommentController do
  def init(opts), do: opts
  def call(conn, _opts), do: conn
end

defmodule TestAppWeb.UserDetailController do
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

    resources "/posts", PostController, only: [:index, :show, :create, :update, :delete]
    resources "/users", UserController, only: [:index, :show]

    resources "/posts/:post_id/comments", CommentController, only: [:index, :show]
    get "/users/:id/detail", UserDetailController, :show
  end
end
