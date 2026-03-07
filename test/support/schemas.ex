defmodule TestApp.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :active, :boolean
    embeds_one :address, TestApp.Address
    embeds_many :social_links, TestApp.SocialLink
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
    field :status, Ecto.Enum, values: [:draft, :published, :archived]
    field :tags, {:array, :string}
    belongs_to :author, TestApp.User
    has_many :comments, TestApp.Comment
    timestamps(type: :utc_datetime)
  end
end

defmodule TestApp.Address do
  use Ecto.Schema

  embedded_schema do
    field :street, :string
    field :city, :string
    field :zip, :string
  end
end

defmodule TestApp.SocialLink do
  use Ecto.Schema

  embedded_schema do
    field :platform, :string
    field :url, :string
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
