defmodule EpochtalkServer.Models.Role do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias EpochtalkServer.Repo
  alias EpochtalkServer.Models.Role
  alias EpochtalkServer.Models.RoleUser

  @derive {Jason.Encoder, only: [:name, :description, :lookup, :priority, :highlight_color, :permissions, :priority_restrictions, :created_at, :updated_at]}
  schema "roles" do
    field :name, :string
    field :description, :string
    field :lookup, :string
    field :priority, :integer
    field :highlight_color, :string

    field :permissions, :map
    field :priority_restrictions, {:array, :integer}

    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end

  def changeset(role, attrs \\ %{}) do
    role
    |> cast(attrs, [:name, :description, :lookup, :priority, :permissions])
    |> validate_required([:name, :description, :lookup, :priority, :permissions])
  end
  def all, do: from(r in Role, order_by: r.id) |> Repo.all
  def by_lookup(lookup), do: Repo.get_by(Role, lookup: lookup)
  def insert([]), do: {:error, "Role list is empty"}
  def insert(%Role{} = role), do: Repo.insert(role)
  def insert([%{}|_] = roles), do: Repo.insert_all(Role, roles)

  def set_permissions(id, permissions) do
    Role
    |> Repo.get(id)
    |> change(%{ permissions: permissions })
    |> Repo.update
  end

  def get_banned_role_id(), do: Repo.one(from(r in Role, select: r.id, where: r.lookup == "banned"))
  def get_newbie_role_id(), do: Repo.one(from(r in Role, select: r.id, where: r.lookup == "newbie"))
  def by_user_id(user_id) do
    query = from ru in RoleUser,
      join: r in Role,
      where: ru.user_id == ^user_id and r.id == ru.role_id,
      select: r,
      order_by: [asc: r.priority]
    case Repo.all(query) do
      [] -> [get_default()] # user has no roles, return default role
      users_roles -> users_roles # user has roles, return them
    end
    |> handle_banned_user_role # if banned, only [ banned ] is returned for roles
  end
  defp get_default(), do: by_lookup("user")

  defp handle_banned_user_role(roles), do: if ban_role = reduce_ban_role(roles), do: [ban_role], else: roles
  defp reduce_ban_role([]), do: nil
  defp reduce_ban_role([role | _]) when role.lookup === "banned", do: role
  defp reduce_ban_role([_ | roles]), do: reduce_ban_role(roles)

  def get_masked_permissions(roles) when is_list(roles), do: Enum.reduce(roles, %{}, &get_masked_permissions(&2, &1))
  def get_masked_permissions(target, source) do
    merge_keys = [:highlight_color, :permissions, :priority, :priority_restrictions]
    filtered_source_keys = Map.keys(source) |> Enum.filter(&Enum.member?(merge_keys, &1))
    target_is_lesser_role = !Map.get(target, :priority) or target.priority > source.priority
    Enum.reduce(filtered_source_keys, %{}, fn key, acc ->
      case key do
        :priority_restrictions -> # merge priority restrictions
          source_pr = source.priority_restrictions
          if target_is_lesser_role and !!source_pr and length(source_pr),
            do: Map.put(acc, :priority_restrictions, source_pr),
            else: Map.put(acc, :priority_restrictions, Map.get(target, :priority_restrictions))
        :permissions -> # merge permissions
          target_permissions = if p = Map.get(target, key), do: p, else: %{}
          Map.put(acc, key, deep_merge(target_permissions, Map.get(source, key)))
        key when key in [:priority, :highlight_color] -> # merge priority/highlight_color
          if target_is_lesser_role, do: Map.put(acc, key, Map.get(source, key)), else: Map.put(acc, key, Map.get(target, key))
      end
    end)
  end

  def deep_merge(left, right), do: Map.merge(left, right, &deep_resolve/3)
  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(_key, left = %{}, right = %{}), do: deep_merge(left, right)
  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right), do: right
end
