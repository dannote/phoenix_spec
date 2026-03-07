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
      status: post.status,
      tags: post.tags,
      author: TestAppWeb.UserJSON.data(post.author),
      reading_time: div(String.length(post.body || ""), 200)
    }
  end
end

defmodule TestAppWeb.UserDetailJSON do
  alias TestApp.User

  Module.register_attribute(__MODULE__, :optional, persist: true)
  Module.register_attribute(__MODULE__, :field_types, persist: true)

  @optional [:age, :avatar_url]
  @field_types reading_time: :integer, avatar_url: :string

  def show(%{user: user}) do
    %{data: data(user)}
  end

  def data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      age: user.age,
      address: user.address,
      social_links: user.social_links,
      avatar_url: if(user.active, do: "/avatars/#{user.id}", else: nil),
      reading_time: calculate_reading_time(user)
    }
  end

  defp calculate_reading_time(_user), do: 5
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
      body: comment.body,
      author_name: comment.user.name,
      author_email: comment.user.email,
      post_title: comment.post.title
    }
  end
end

defmodule TestAppWeb.CommentDetailJSON do
  alias TestApp.Comment

  def show(%{comment: %Comment{} = comment}) do
    %{data: data(comment)}
  end

  defp data(comment) do
    %{
      id: comment.id,
      body: comment.body
    }
  end
end

defmodule TestAppWeb.PostSummaryJSON do
  alias TestApp.Post

  def show(%{post: post}) do
    %{data: %{id: post.id, title: post.title, published: post.published}}
  end
end

defmodule TestAppWeb.MessageJSON do
  alias TestApp.ImageMessage
  alias TestApp.TextMessage

  def index(%{messages: messages}) do
    %{data: for(message <- messages, do: data(message))}
  end

  def show(%{message: message}) do
    %{data: data(message)}
  end

  def data(%TextMessage{} = msg) do
    %{
      id: msg.id,
      type: "text",
      text: msg.text,
      sender: msg.sender
    }
  end

  def data(%ImageMessage{} = msg) do
    %{
      id: msg.id,
      type: "image",
      url: msg.url,
      alt_text: msg.alt_text,
      width: msg.width,
      height: msg.height,
      sender: msg.sender
    }
  end
end

defmodule TestAppWeb.PostMetaJSON do
  alias TestApp.Post

  def show(%{post: %Post{} = post}) do
    %{
      data: %{
        author: %{
          name: post.author.name,
          email: post.author.email
        },
        stats: %{
          views: post.view_count,
          comments: post.comments
        }
      }
    }
  end
end
