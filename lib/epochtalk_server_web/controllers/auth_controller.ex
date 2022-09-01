defmodule EpochtalkServerWeb.AuthController do
  use EpochtalkServerWeb, :controller
  alias EpochtalkServer.Model.User
  alias EpochtalkServer.Repo
  alias EpochtalkServer.Auth.Guardian

  alias EpochtalkServerWeb.CustomErrors.{InvalidCredentials, NotLoggedIn}
  alias EpochtalkServerWeb.ErrorView

  def username(conn, %{"username" => username}) do
    username_found = username
    |> User.with_username_exists?

    render(conn, "search.json", found: username_found)
  end
  def email(conn, %{"email" => email}) do
    email_found = email
    |> User.with_email_exists?

    render(conn, "search.json", found: email_found)
  end
  def register(conn, attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        conn
        |> render("show.json", user: user)
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_view(ErrorView)
        |> render("400.json", %{message: inspect(changeset.errors)})
    end
  end
  def authenticate(conn, _attrs) do
    user = conn
    |> Guardian.Plug.current_resource

    token = conn
    |> Guardian.Plug.current_token

    user = Map.put(user, :token, token)

    # TODO: check for empty roles first
    # add default role
    user = Map.put(user, :roles, ["user"])

    conn
    |> render("credentials.json", user: user)
  end
  def logout(conn, _attrs) do
    if Guardian.Plug.authenticated?(conn) do
      # TODO: check if user is on page that requires auth
      conn
      |> Guardian.Plug.sign_out
      |> render("logout.json")
    else
      raise(NotLoggedIn)
    end
  end
  def login(conn, user_params) when not is_map_key(user_params, "rememberMe") do
    login(conn, Map.put(user_params, "rememberMe", false))
  end
  def login(conn, %{"username" => username, "password" => password} = user_params) do
    if user = User.by_username_and_password(username, password) do
      # TODO: check confirmation token
      # TODO: check ban expiration
      # TODO: get moderated boards
      log_in_user(conn, user, user_params)
    else
      raise(InvalidCredentials)
    end
  end
  defp log_in_user(conn, user, %{"rememberMe" => remember_me}) do
    datetime = NaiveDateTime.utc_now
    session_id = UUID.uuid1()
    decoded_token = %{ user_id: user.id, session_id: session_id, timestamp: datetime }

    # token expiration based on remember_me
    ttl = case remember_me do
      # set longer expiration
      "true" -> {4, :weeks}
      # set default expiration
      _ -> {1, :day}
    end

    token = conn
    |> Guardian.Plug.sign_in(decoded_token, %{}, ttl: ttl)
    |> Guardian.Plug.current_token

    user = Map.put(user, :token, token)

    # TODO: check for empty roles first
    # add default role
    user = Map.put(user, :roles, ["user"])

    conn
    |> render("credentials.json", user: user)
  end
end