defmodule EpochtalkServerWeb.RoleController do
  use EpochtalkServerWeb, :controller

  @moduledoc """
  Controller For `Role` related API requests
  """
  alias EpochtalkServer.Auth.Guardian
  alias EpochtalkServerWeb.ErrorHelpers
  alias EpochtalkServerWeb.Helpers.Validate
  alias EpochtalkServer.Models.Role
  alias EpochtalkServer.Models.RolePermission

  @doc """
  Used to update a specific `Role`
  """
  def update(
        conn,
        %{
          "id" => _,
          "permissions" => permissions,
          "priority_restrictions" => priority_restrictions
        } = attrs
      ) do
    with id <- Validate.cast(attrs, "id", :integer, min: 1),
         priority_restrictions <-
           Validate.cast(attrs, "priority_restrictions", :integer, array: true),
         {:auth, _user} <- {:auth, Guardian.Plug.current_resource(conn)},
         {:ok, data} <- RolePermission.modify_by_role(%Role{id: id, permissions: permissions}) do
      render(conn, "update.json", data: data)
    else
      {:auth, nil} ->
        ErrorHelpers.render_json_error(conn, 400, "Not logged in, cannot update role")
    end
  end
end
