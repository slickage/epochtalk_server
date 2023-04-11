defmodule EpochtalkServerWeb.SessionTest do
  @one_day_in_seconds 1 * 24 * 60 * 60
  @almost_one_day_in_seconds @one_day_in_seconds - 100
  @four_weeks_in_seconds 4 * 7 * @one_day_in_seconds
  @almost_four_weeks_in_seconds @four_weeks_in_seconds - 100
  use EpochtalkServerWeb.ConnCase, async: false
  alias EpochtalkServer.Session

  describe "get_resource/2" do
    test "errors when session_id is invalid", %{user: user} do
      session_id = "bogussessionid"

      assert Session.get_resource(user.id, session_id) ==
               {:error, "No session for user_id #{user.id} with id #{session_id}"}
    end

    @tag :authenticated
    test "errors when user id is invalid", %{conn: conn} do
      user_id = 0
      # get session_id (jti) from conn
      session_id = conn.private.guardian_default_claims["jti"]

      assert Session.get_resource(user_id, session_id) ==
               {:error, "No session for user_id #{user_id} with id #{session_id}"}
    end

    @tag :authenticated
    test "gets a valid resource when authenticated", %{conn: conn, authed_user: authed_user} do
      # get session_id (jti) from conn
      session_id = conn.private.guardian_default_claims["jti"]
      {:ok, resource_user} = Session.get_resource(authed_user.id, session_id)
      assert authed_user.id == resource_user.id
    end
  end

  describe "delete/1" do
    @tag :authenticated
    test "deletes authenticated user's session", %{conn: conn, authed_user: authed_user} do
      session_id = conn.private.guardian_default_claims["jti"]
      {:ok, resource} = Session.get_resource(authed_user.id, session_id)
      %{id: session_user_id, username: session_user_username} = resource
      assert session_user_id == authed_user.id
      assert session_user_username == authed_user.username

      # delete user session indirectly via logout route
      #   this is done rather than calling Session.delete
      #   because guardian does not load the resource
      #   when calling Session.delete directly
      unauthed_conn = delete(conn, Routes.user_path(conn, :logout))
      assert Guardian.Plug.authenticated?(unauthed_conn) == false
      unauthed_resource = Session.get_resource(authed_user.id, session_id)

      assert unauthed_resource ==
               {:error, "No session for user_id #{authed_user.id} with id #{session_id}"}
    end
  end

  describe "create/3 session expiration" do
    test "deletes an expired user session when logging in", %{conn: conn, user: user} do
      remember_me = false
      # create session that should be deleted
      {:ok, authed_user_to_delete, _token, authed_conn_to_delete} = Session.create(user, remember_me, conn)
      session_id_to_delete = authed_conn_to_delete.private.guardian_default_claims["jti"]
      # create session that shouldn't be deleted
      {:ok, authed_user_to_persist, _token, authed_conn_to_persist} = Session.create(user, remember_me, conn)
      session_id_to_persist = authed_conn_to_persist.private.guardian_default_claims["jti"]
      # check that all sessions are active
      {:ok, resource_to_delete} = Session.get_resource(user.id, session_id_to_delete)
      %{id: session_user_id_to_delete, username: session_user_username_to_delete} = resource_to_delete
      assert session_user_id_to_delete == user.id
      assert session_user_username_to_delete == user.username
      {:ok, resource_to_persist} = Session.get_resource(user.id, session_id_to_persist)
      %{id: session_user_id_to_persist, username: session_user_username_to_persist} = resource_to_persist
      assert session_user_id_to_persist == user.id
      assert session_user_username_to_persist == user.username
      # change expiration of session to delete to UTC 0
      expiration_utc = 0
      Redix.command(:redix, ["ZADD", "user:#{user.id}:sessions", expiration_utc, session_id_to_delete])
      # create a new session (should delete expired sessions)
      {:ok, new_authed_user, _token, new_authed_conn} = Session.create(user, remember_me, conn)
      new_session_id = new_authed_conn.private.guardian_default_claims["jti"]
      # check that active sessions are still active
      {:ok, resource_to_persist} = Session.get_resource(user.id, session_id_to_persist)
      %{id: session_user_id_to_persist, username: session_user_username_to_persist} = resource_to_persist
      assert session_user_id_to_persist == user.id
      assert session_user_username_to_persist == user.username
      authenticate_persisted_conn = get(authed_conn_to_persist, Routes.user_path(authed_conn_to_persist, :authenticate))
      assert user.id == json_response(authenticate_persisted_conn, 200)["id"]
      {:ok, new_resource} = Session.get_resource(user.id, new_session_id)
      %{id: new_session_user_id, username: new_session_user_username} = new_resource
      assert new_session_user_id == user.id
      assert new_session_user_username == user.username
      new_authenticate_conn = get(new_authed_conn, Routes.user_path(new_authed_conn, :authenticate))
      assert user.id == json_response(new_authenticate_conn, 200)["id"]
      # check that expired session is not active
      unauthed_resource = Session.get_resource(user.id, session_id_to_delete)
      assert unauthed_resource ==
               {:error, "No session for user_id #{user.id} with id #{session_id_to_delete}"}
      authenticate_deleted_conn = get(authed_conn_to_delete, Routes.user_path(authed_conn_to_delete, :authenticate))
      assert %{"error" => "Unauthorized", "message" => "No resource found"} = json_response(authenticate_deleted_conn, 401)
    end
  end

  describe "create/3 expiration/ttl" do
    setup [:flush_redis]

    test "creates a user session without remember me (< 1 day ttl)", %{conn: conn, user: user} do
      remember_me = false
      {:ok, authed_user, _token, _authed_conn} = Session.create(user, remember_me, conn)
      user_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}"])
      roles_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:roles"])
      moderating_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:moderating"])
      baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:baninfo"])
      sessions_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:sessions"])

      assert user_ttl > @almost_one_day_in_seconds
      assert user_ttl <= @one_day_in_seconds
      assert roles_ttl > @almost_one_day_in_seconds
      assert roles_ttl <= @one_day_in_seconds
      assert moderating_ttl <= @one_day_in_seconds
      assert baninfo_ttl <= @one_day_in_seconds
      assert sessions_ttl > @almost_one_day_in_seconds
      assert sessions_ttl <= @one_day_in_seconds
    end

    test "creates a user session with remember me (< 4 week ttl)", %{conn: conn, user: user} do
      remember_me = true
      {:ok, authed_user, _token, _authed_conn} = Session.create(user, remember_me, conn)
      user_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}"])
      roles_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:roles"])
      moderating_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:moderating"])
      baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:baninfo"])
      sessions_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:sessions"])

      assert user_ttl > @almost_four_weeks_in_seconds
      assert user_ttl <= @four_weeks_in_seconds
      assert roles_ttl > @almost_four_weeks_in_seconds
      assert roles_ttl <= @four_weeks_in_seconds
      assert moderating_ttl <= @four_weeks_in_seconds
      assert baninfo_ttl <= @four_weeks_in_seconds
      assert sessions_ttl > @almost_four_weeks_in_seconds
      assert sessions_ttl <= @four_weeks_in_seconds
    end

    test "handles updating ttl", %{conn: conn, user: user} do
      remember_me_1 = false
      {:ok, authed_user_1, _token, _authed_conn} = Session.create(user, remember_me_1, conn)
      user_ttl_1 = Redix.command!(:redix, ["TTL", "user:#{authed_user_1.id}"])
      roles_ttl_1 = Redix.command!(:redix, ["TTL", "user:#{authed_user_1.id}:roles"])
      moderating_ttl_1 = Redix.command!(:redix, ["TTL", "user:#{authed_user_1.id}:moderating"])
      baninfo_ttl_1 = Redix.command!(:redix, ["TTL", "user:#{authed_user_1.id}:baninfo"])
      sessions_ttl_1 = Redix.command!(:redix, ["TTL", "user:#{authed_user_1.id}:sessions"])

      assert user_ttl_1 > @almost_one_day_in_seconds
      assert user_ttl_1 <= @one_day_in_seconds
      assert roles_ttl_1 > @almost_one_day_in_seconds
      assert roles_ttl_1 <= @one_day_in_seconds
      assert moderating_ttl_1 <= @one_day_in_seconds
      assert baninfo_ttl_1 <= @one_day_in_seconds
      assert sessions_ttl_1 > @almost_one_day_in_seconds
      assert sessions_ttl_1 <= @one_day_in_seconds

      remember_me_2 = true
      {:ok, authed_user_2, _token, _authed_conn} = Session.create(user, remember_me_2, conn)
      user_ttl_2 = Redix.command!(:redix, ["TTL", "user:#{authed_user_2.id}"])
      roles_ttl_2 = Redix.command!(:redix, ["TTL", "user:#{authed_user_2.id}:roles"])
      moderating_ttl_2 = Redix.command!(:redix, ["TTL", "user:#{authed_user_2.id}:moderating"])
      baninfo_ttl_2 = Redix.command!(:redix, ["TTL", "user:#{authed_user_2.id}:baninfo"])
      sessions_ttl_2 = Redix.command!(:redix, ["TTL", "user:#{authed_user_2.id}:sessions"])

      assert user_ttl_2 > @almost_four_weeks_in_seconds
      assert user_ttl_2 <= @four_weeks_in_seconds
      assert roles_ttl_2 > @almost_four_weeks_in_seconds
      assert roles_ttl_2 <= @four_weeks_in_seconds
      assert moderating_ttl_2 <= @four_weeks_in_seconds
      assert baninfo_ttl_2 <= @four_weeks_in_seconds
      assert sessions_ttl_2 > @almost_four_weeks_in_seconds
      assert sessions_ttl_2 <= @four_weeks_in_seconds

      remember_me_3 = false
      {:ok, authed_user_3, _token, _authed_conn} = Session.create(user, remember_me_3, conn)
      user_ttl_3 = Redix.command!(:redix, ["TTL", "user:#{authed_user_3.id}"])
      roles_ttl_3 = Redix.command!(:redix, ["TTL", "user:#{authed_user_3.id}:roles"])
      moderating_ttl_3 = Redix.command!(:redix, ["TTL", "user:#{authed_user_3.id}:moderating"])
      baninfo_ttl_3 = Redix.command!(:redix, ["TTL", "user:#{authed_user_3.id}:baninfo"])
      sessions_ttl_3 = Redix.command!(:redix, ["TTL", "user:#{authed_user_3.id}:sessions"])

      assert user_ttl_3 > @almost_four_weeks_in_seconds
      assert user_ttl_3 <= @four_weeks_in_seconds
      assert roles_ttl_3 > @almost_four_weeks_in_seconds
      assert roles_ttl_3 <= @four_weeks_in_seconds
      assert moderating_ttl_3 <= @four_weeks_in_seconds
      assert baninfo_ttl_3 <= @four_weeks_in_seconds
      assert sessions_ttl_3 > @almost_four_weeks_in_seconds
      assert sessions_ttl_3 <= @four_weeks_in_seconds
    end

    @tag :banned
    test "handles baninfo ttl and ban_expiration without remember me (< 1 day ttl)", %{
      conn: conn,
      user_attrs: user_attrs,
      user: user
    } do
      pre_ban_baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      pre_ban_ban_expiration =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "ban_expiration"])

      post(
        conn,
        Routes.user_path(conn, :login, %{
          username: user_attrs.username,
          password: user_attrs.password
        })
      )

      baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      ban_expiration =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "ban_expiration"])

      assert is_nil(pre_ban_ban_expiration)
      assert ban_expiration == "9999-12-31 00:00:00"
      assert pre_ban_baninfo_ttl == -2
      assert baninfo_ttl <= @one_day_in_seconds
      assert baninfo_ttl > @almost_one_day_in_seconds
    end

    @tag :banned
    test "handles baninfo ttl and ban_expiration with remember me (< 4 weeks ttl)", %{
      conn: conn,
      user_attrs: user_attrs,
      user: user
    } do
      pre_ban_baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      pre_ban_ban_expiration =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "ban_expiration"])

      post(
        conn,
        Routes.user_path(conn, :login, %{
          username: user_attrs.username,
          password: user_attrs.password,
          rememberMe: true
        })
      )

      baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      ban_expiration =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "ban_expiration"])

      assert is_nil(pre_ban_ban_expiration)
      assert ban_expiration == "9999-12-31 00:00:00"
      assert pre_ban_baninfo_ttl == -2
      assert baninfo_ttl <= @four_weeks_in_seconds
      assert baninfo_ttl > @almost_four_weeks_in_seconds
    end

    @tag :malicious
    test "handles baninfo ttl and malicious score without remember me (< 1 day ttl)", %{
      conn: conn,
      user: user,
      malicious_user_changeset: malicious_user_changeset
    } do
      pre_malicious_baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      pre_malicious_malicious_score =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "malicious_score"])

      malicious_user = Map.put(user, :malicious_score, malicious_user_changeset.malicious_score)
      remember_me = false
      {:ok, authed_user, _token, _authed_conn} = Session.create(malicious_user, remember_me, conn)

      malicious_score_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:baninfo"])

      malicious_score =
        Redix.command!(:redix, ["HGET", "user:#{authed_user.id}:baninfo", "malicious_score"])

      assert is_nil(pre_malicious_malicious_score)
      assert malicious_score == "4.0416"
      assert pre_malicious_baninfo_ttl == -2
      assert malicious_score_ttl <= @one_day_in_seconds
      assert malicious_score_ttl > @almost_one_day_in_seconds
    end

    @tag :malicious
    test "handles baninfo ttl and malicious score with remember me (< 4 weeks ttl)", %{
      conn: conn,
      user: user,
      malicious_user_changeset: malicious_user_changeset
    } do
      pre_malicious_baninfo_ttl = Redix.command!(:redix, ["TTL", "user:#{user.id}:baninfo"])

      pre_malicious_malicious_score =
        Redix.command!(:redix, ["HGET", "user:#{user.id}:baninfo", "malicious_score"])

      malicious_user = Map.put(user, :malicious_score, malicious_user_changeset.malicious_score)
      remember_me = true
      {:ok, authed_user, _token, _authed_conn} = Session.create(malicious_user, remember_me, conn)

      malicious_score_ttl = Redix.command!(:redix, ["TTL", "user:#{authed_user.id}:baninfo"])

      malicious_score =
        Redix.command!(:redix, ["HGET", "user:#{authed_user.id}:baninfo", "malicious_score"])

      assert is_nil(pre_malicious_malicious_score)
      assert malicious_score == "4.0416"
      assert pre_malicious_baninfo_ttl == -2
      assert malicious_score_ttl <= @four_weeks_in_seconds
      assert malicious_score_ttl > @almost_four_weeks_in_seconds
    end
  end

  defp flush_redis(_) do
    Redix.command!(:redix, ["FLUSHALL"])
    :ok
  end
end
