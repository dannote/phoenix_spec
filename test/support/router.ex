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

defmodule TestAppWeb.FlatParamsController do
  alias TestApp.Post

  def create(conn, %{"title" => title, "body" => body}) do
    Ecto.Changeset.cast(%Post{}, %{title: title, body: body}, [:title, :body])
    conn
  end
end

defmodule TestAppWeb.InlinePostController do
  alias TestApp.Post

  def init(opts), do: opts
  def call(conn, _opts), do: conn

  def show(conn, %{"id" => _id}) do
    post = %Post{}
    body = %{id: post.id, title: post.title}
    Phoenix.Controller.json(conn, data: body)
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

defmodule TestAppWeb.MessageController do
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
    get "/inline-posts/:id", InlinePostController, :show
    resources "/users", UserController, only: [:index, :show]

    resources "/posts/:post_id/comments", CommentController, only: [:index, :show]
    get "/users/:id/detail", UserDetailController, :show
    resources "/messages", MessageController, only: [:index, :show]
  end
end
