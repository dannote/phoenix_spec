defmodule TestAppWeb.UserJSON do
  alias TestApp.User

  def index(%{users: users}) do
    %{data: for(user <- users, do: data(user))}
  end

  def show(%{user: user}) do
    %{data: data(user)}
  end

  def data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email
    }
  end
end

defmodule TestAppWeb.PostJSON do
  alias TestApp.Post

  def index(%{posts: posts}) do
    %{data: for(post <- posts, do: data(post))}
  end

  def show(%{post: post}) do
    %{data: data(post)}
  end

  def create(%{post: post}) do
    %{data: data(post)}
  end

  defp data(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      body: post.body,
      view_count: post.view_count,
      published: post.published,
      published_at: post.published_at,
      author: TestAppWeb.UserJSON.data(post.author)
    }
  end
end

defmodule TestAppWeb.CommentJSON do
  alias TestApp.Comment

  def index(%{comments: comments}) do
    %{data: for(comment <- comments, do: data(comment))}
  end

  def show(%{comment: comment}) do
    %{data: data(comment)}
  end

  defp data(%Comment{} = comment) do
    %{
      id: comment.id,
      body: comment.body
    }
  end
end
