defmodule EpochtalkServerWeb.NotificationController do
  use EpochtalkServerWeb, :controller
  @moduledoc """
  Controller For `Notification` related API requests
  """
  alias EpochtalkServer.Auth.Guardian
  alias EpochtalkServer.Models.Notification
  alias EpochtalkServerWeb.ErrorHelpers
  alias EpochtalkServerWeb.Helpers.Validate

  @doc """
  Used to retrieve `Notification` counts for a specific `User`
  """
  def counts(conn, attrs) do
    with max <- Validate.optional_pos_int(attrs["max"], "max"),
         {:auth, user} <- {:auth, Guardian.Plug.current_resource(conn)},
      do: render(conn, "counts.json", data: Notification.counts_by_user_id(user.id, max: max || 99)),
      else: ({:auth, nil} -> ErrorHelpers.render_json_error(conn, 400, "Not logged in, cannot fetch notification counts"))
  end

  @doc """
  Used to dismiss `Notification` counts for a specific `User`
  TODO(akinsey): add websocket broadcast to "refreshMentions"
  """
  def dismiss(conn, %{"id" => id}) do
    with {_count, nil} <- Notification.dismiss(id),
      do: render(conn, "dismiss.json", data: %{success: true}),
      else: (_ -> ErrorHelpers.render_json_error(conn, 500, "Something went wrong, could not dismiss notifications"))
  end
  def dismiss(conn, %{"type" => type}) do
    with {:auth, user} <- {:auth, Guardian.Plug.current_resource(conn)},
         {_count, nil} <- Notification.dismiss_type_by_user_id(user.id, type) do
      render(conn, "dismiss.json", data: %{success: true})
    else
      {:auth, nil} -> ErrorHelpers.render_json_error(conn, 400, "Not logged in, cannot dismiss notification counts")
      {:error, :invalid_notification_type} -> ErrorHelpers.render_json_error(conn, 400, "Cannot dismiss, invalid notification type")
      _ -> ErrorHelpers.render_json_error(conn, 500, "Something went wrong, could not dismiss notifications")
    end
  end
end
