defmodule EpochtalkServerWeb.Controllers.UserJSON do
  alias EpochtalkServer.Models.Role
  alias EpochtalkServer.Models.User

  @moduledoc """
  Renders and formats `User` data, in JSON format for frontend
  """

  @doc """
  Renders formatted user JSON. Takes in a `User` with all associations preloaded
  and outputs formatted user json used for auth. Masks all user's roles to generate
  correct permissions set.
  """
  def user(%{user: user, token: token}), do: format_user_reply(user, token)

  @doc """
  Renders formatted user JSON for find proxy
  """
  def find_proxy(%{user: user}) do
    parsed_signature =
      if user.signature,
        do: EpochtalkServer.BBCParser.parse(user.signature),
        else: nil

    gender =
      case Map.get(user, :gender) do
        1 -> "Male"
        2 -> "Female"
        _ -> nil
      end

    dob =
      case d = Map.get(user, :dob) do
        ~D[0001-01-01] -> nil
        _ -> d
      end

    last_active = calculate_last_active(user)

    position = user.group_name || user.group_name_2
    position_color = user.group_color || user.group_color_2

    user
    |> Map.put(:signature, parsed_signature)
    |> Map.put(:gender, gender)
    |> Map.put(:dob, dob)
    |> Map.put(:last_active, last_active)
    |> Map.put(:position, position)
    |> Map.put(:position_color, position_color)
    |> Map.delete(:last_login)
    |> Map.delete(:show_online)
    |> Map.delete(:group_name)
    |> Map.delete(:group_name_2)
    |> Map.delete(:group_color)
    |> Map.delete(:group_color_2)
  end

  @doc """
  Renders formatted user JSON for find
  """
  def find(%{
        user: user,
        activity: activity,
        metric_rank_maps: metric_rank_maps,
        ranks: ranks,
        show_hidden: show_hidden
      }) do
    highest_role = user.roles |> Enum.sort_by(& &1.priority) |> List.first()
    [post_count | _] = metric_rank_maps

    # handle missing profile/preferences row
    user = user |> Map.put(:profile, user.profile || %{})
    user = user |> Map.put(:preferences, user.preferences || %{})

    # fetch potentially nested fields
    fields = Map.get(user.profile, :fields, %{})

    ret = %{
      id: user.id,
      username: user.username,
      created_at: user.created_at,
      updated_at: user.updated_at,
      avatar: Map.get(user.profile, :avatar),
      post_count: Map.get(user.profile, :post_count),
      last_active: Map.get(user.profile, :last_active),
      dob: fields["dob"],
      name: fields["name"],
      gender: fields["gender"],
      website: fields["website"],
      language: fields["language"],
      location: fields["location"],
      role_name: Map.get(highest_role, :name),
      role_highlight_color: Map.get(highest_role, :highlight_color),
      roles: Enum.map(user.roles, & &1.lookup),
      priority: Map.get(highest_role, :priority),
      metadata: %{
        rank_metric_maps: post_count.maps,
        ranks: ranks
      },
      activity: activity
    }

    if show_hidden,
      do:
        ret
        |> Map.put(:email, user.email)
        |> Map.put(:threads_per_page, Map.get(user.preferences, :threads_per_page) || 25)
        |> Map.put(:posts_per_page, Map.get(user.preferences, :posts_per_page) || 25)
        |> Map.put(:ignored_boards, Map.get(user.preferences, :ignored_boards) || [])
        |> Map.put(:collapsed_categories, Map.get(user.preferences, :collapsed_categories) || []),
      else: ret
  end

  @doc """
  Renders formatted JSON response for registration confirmation.
  ## Example
    iex> EpochtalkServerWeb.Controllers.UserJSON.register_with_verify(%{user: %User{ username: "Test" }})
    %{
      username: "Test",
      confirm_token: true,
      message: "Successfully registered, please confirm account to login."
    }
  """
  def register_with_verify(%{user: user}) do
    %{
      username: user.username,
      confirm_token: true,
      message: "Successfully registered, please confirm account to login."
    }
  end

  @doc """
  Renders whatever data it is passed when template not found. Data pass through
  for rendering misc responses (ex: {found: true} or {success: true})
  ## Example
      iex> EpochtalkServerWeb.Controllers.UserJSON.data(%{data: %{found: true}})
      %{found: true}
      iex> EpochtalkServerWeb.Controllers.UserJSON.data(%{data: %{success: true}})
      %{success: true}
  """
  def data(%{conn: %{assigns: %{data: data}}}), do: data
  def data(%{data: data}), do: data

  # Format reply - from Models.User (login, register)
  defp format_user_reply(%User{} = user, token) do
    avatar = if user.profile, do: user.profile.avatar, else: nil

    moderating =
      if length(user.moderating) != 0, do: Enum.map(user.moderating, & &1.board_id), else: nil

    ban_expiration = if user.ban_info, do: user.ban_info.expiration, else: nil
    malicious_score = if user.malicious_score, do: user.malicious_score, else: nil
    format_user_reply(user, token, {avatar, moderating, ban_expiration, malicious_score})
  end

  # Format reply - from user stored by Guardian (authenticate)
  defp format_user_reply(user, token) do
    avatar = Map.get(user, :avatar)

    moderating =
      if Map.get(user, :moderating) && length(user.moderating) != 0,
        do: user.moderating,
        else: nil

    ban_expiration = Map.get(user, :ban_expiration)
    malicious_score = Map.get(user, :malicious_score)
    format_user_reply(user, token, {avatar, moderating, ban_expiration, malicious_score})
  end

  # Format reply - common user formatting functionality, outputs user reply map
  defp format_user_reply(user, token, {avatar, moderating, ban_expiration, malicious_score}) do
    reply = %{
      token: token,
      id: user.id,
      username: user.username,
      permissions: Role.get_masked_permissions(user.roles),
      roles: Enum.map(user.roles, & &1.lookup)
    }

    # only append avatar, moderating, ban_expiration and malicious_score if present
    reply = if avatar, do: Map.put(reply, :avatar, avatar), else: reply
    reply = if moderating, do: Map.put(reply, :moderating, moderating), else: reply
    reply = if ban_expiration, do: Map.put(reply, :ban_expiration, ban_expiration), else: reply
    reply = if malicious_score, do: Map.put(reply, :malicious_score, malicious_score), else: reply
    reply
  end

  defp calculate_last_active(user) when is_map(user) do
    {:ok, last_login} = DateTime.from_unix(user.last_login, :millisecond)
    last_login_past_72_hours = DateTime.diff(DateTime.utc_now(), last_login, :hour) > 72

    if user.show_online == 1 or last_login_past_72_hours, do: user.last_login
  end
end
