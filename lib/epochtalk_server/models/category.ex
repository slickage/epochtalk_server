defmodule EpochtalkServer.Models.Category do
  use Ecto.Schema
  import Ecto.Changeset
  alias EpochtalkServer.Repo
  alias EpochtalkServer.Models.Board
  alias EpochtalkServer.Models.Category
  alias EpochtalkServer.Models.BoardMapping

  schema "categories" do
    field :name, :string
    field :view_order, :integer
    field :viewable_by, :integer
    field :postable_by, :integer
    field :created_at, :naive_datetime
    field :imported_at, :naive_datetime
    field :updated_at, :naive_datetime
    field :meta, :map
    many_to_many :boards, Board, join_through: BoardMapping
  end

  ## === Changesets Functions ===

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:id, :name, :view_order, :viewable_by, :postable_by, :created_at, :imported_at, :updated_at, :meta])
    |> unique_constraint(:id, name: :categories_pkey)
  end

  def create_changeset(category, attrs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    attrs = attrs
    |> Map.put(:created_at, now)
    |> Map.put(:updated_at, now)
    category
    |> cast(attrs, [:name, :viewable_by, :created_at, :updated_at])
  end

  def update_for_board_mapping_changeset(category, attrs) do
    category
    |> cast(attrs, [:id, :name, :view_order, :viewable_by])
    |> unique_constraint(:id, name: :categories_pkey)
  end

  ## === Database Functions ===

  def insert(%Category{} = category), do: Repo.insert(category)

  def create(attrs) do
    category_cs = create_changeset(%Category{}, attrs)
    Repo.insert!(category_cs)
  end

  def update_for_board_mapping(%{ id: id } = category_map) do
    %Category{ id: id }
    |> update_for_board_mapping_changeset(category_map)
    |> Repo.update
  end
end
