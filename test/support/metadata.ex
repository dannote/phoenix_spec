defmodule TestAppWeb.MetadataJSON do
  alias TestApp.User

  Module.register_attribute(__MODULE__, :field_metadata, persist: true)
  Module.register_attribute(__MODULE__, :schema_metadata, persist: true)

  @schema_metadata description: "A documented user",
                   additionalProperties: false,
                   examples: [%{name: "Ada"}]
  @field_metadata name: [description: "Display name", examples: ["Ada"]],
                  address: [description: "Postal address", additionalProperties: false],
                  author: [description: "Author", examples: [%{id: 1}]],
                  authors: [description: "Authors"],
                  settings: [additionalProperties: %{type: "string"}],
                  active: [examples: [false, nil]]

  def show(%{user: user}), do: %{data: data(user)}

  def data(%User{} = user) do
    %{
      name: user.name,
      address: user.address,
      author: TestAppWeb.UserJSON.data(user),
      authors: for(u <- [user], do: TestAppWeb.UserJSON.data(u)),
      settings: %{},
      active: user.active
    }
  end
end

defmodule TestAppWeb.MetadataController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params), do: conn
end

defmodule TestAppWeb.MetadataVariantJSON do
  Module.register_attribute(__MODULE__, :field_metadata, persist: true)
  Module.register_attribute(__MODULE__, :schema_metadata, persist: true)

  @schema_metadata description: "Message", additionalProperties: false
  @field_metadata id: [description: "Identifier", examples: [1]]

  def show(%{message: message}), do: %{data: data(message)}
  def data(%TestApp.TextMessage{} = message), do: %{id: message.id, text: message.text}
  def data(%TestApp.ImageMessage{} = message), do: %{id: message.id, url: message.url}
end

defmodule TestAppWeb.MetadataVariantController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params), do: conn
end

defmodule TestAppWeb.MetadataRouter do
  @moduledoc false

  use Phoenix.Router

  get("/users/:id", TestAppWeb.UserController, :show)
  get("/metadata/:id", TestAppWeb.MetadataController, :show)
  get("/variants/:id", TestAppWeb.MetadataVariantController, :show)
end
