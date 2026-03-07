defmodule TestApp.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :active, :boolean
    timestamps(type: :utc_datetime)
  end
end

defmodule TestApp.Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :body, :string
    field :view_count, :integer
    field :published, :boolean
    field :published_at, :utc_datetime
    belongs_to :author, TestApp.User
    has_many :comments, TestApp.Comment
    timestamps(type: :utc_datetime)
  end
end

defmodule TestApp.Comment do
  use Ecto.Schema

  schema "comments" do
    field :body, :string
    belongs_to :post, TestApp.Post
    belongs_to :user, TestApp.User
    timestamps(type: :utc_datetime)
  end
end
