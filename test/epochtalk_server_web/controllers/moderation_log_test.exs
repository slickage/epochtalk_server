defmodule Test.EpochtalkServerWeb.Controllers.ModerationLog do
  use Test.Support.ConnCase, async: true
  alias EpochtalkServer.Models.ModerationLog
  import Test.Support.Factory

  ## helper functions
  defp stringify_keys_deep(map) do
    map
    |> Enum.reduce(%{}, fn {k, v}, m ->
      v = if is_map(v), do: stringify_keys_deep(v), else: v
      Map.put(m, to_string(k), v)
    end)
  end

  defp compare(result_moderation_log, factory_moderation_log, options \\ []) do
    # process options
    defaults = %{convert_date: [], stringify: []}
    %{convert_date: convert_date_list, stringify: stringify_list} = Enum.into(options, defaults)

    # check "action_obj" key
    factory_moderation_log.action_obj
    |> Enum.each(fn {k, v} ->
      result_value = result_moderation_log["action_obj"] |> Map.get(to_string(k))
      # convert specified factory atom-keyed maps in list to string-keyed
      v =
        if Enum.member?(stringify_list, k) do
          v |> Enum.map(fn e -> stringify_keys_deep(e) end)
        else
          v
        end

      # convert specified result dates to NaiveDateTime
      result_value =
        if Enum.member?(convert_date_list, k) do
          result_value |> NaiveDateTime.from_iso8601!()
        else
          result_value
        end

      assert result_value == v
    end)

    # check all other keys
    assert result_moderation_log["action_api_method"] == factory_moderation_log.action_api_method
    assert result_moderation_log["action_api_url"] == factory_moderation_log.action_api_url

    assert result_moderation_log["action_display_text"] ==
             factory_moderation_log.action_display_text

    assert result_moderation_log["action_display_url"] ==
             factory_moderation_log.action_display_url

    assert result_moderation_log["action_taken_at"] |> NaiveDateTime.from_iso8601!() ==
             factory_moderation_log.action_taken_at

    assert result_moderation_log["action_type"] == factory_moderation_log.action_type
    assert result_moderation_log["mod_id"] == factory_moderation_log.mod_id
    assert result_moderation_log["mod_ip"] == factory_moderation_log.mod_ip
    assert result_moderation_log["mod_username"] == factory_moderation_log.mod_username
  end

  defp page_response_list(conn, query) do
    conn
    |> get(Routes.moderation_log_path(conn, :page, query))
    |> json_response(200)
    |> Map.get("moderation_logs")
  end

  defp page_response(conn, query) do
    page_response_list(conn, query)
    |> List.first()
  end

  ## tests
  describe "create/1" do
    test "creates moderation_log entry", %{users: %{admin_user: admin_user}} do
      mod_address = "127.0.0.2"

      attrs = %{
        mod: %{username: admin_user.username, id: 1, ip: mod_address},
        action: %{
          api_url: "/api/boards/all",
          api_method: "post",
          type: "adminBoards.updateCategories",
          obj: %{}
        }
      }

      {:ok, moderation_log} = ModerationLog.create(attrs)
      assert moderation_log.mod_username == attrs.mod.username
      assert moderation_log.mod_id == attrs.mod.id
      assert moderation_log.mod_ip == attrs.mod.ip
      assert moderation_log.action_api_url == attrs.action.api_url
      assert moderation_log.action_api_method == attrs.action.api_method
      assert moderation_log.action_obj == attrs.action.obj
      assert moderation_log.action_type == attrs.action.type
      assert moderation_log.action_display_text == "updated boards and categories"
      assert moderation_log.action_display_url == "admin-management.boards"
    end

    test "creates moderation_log using helper data_query function", %{
      users: %{user: user, admin_user: admin_user}
    } do
      mod_address = "127.0.0.2"
      board = build(:board)

      attrs = %{
        mod: %{username: admin_user.username, id: 1, ip: mod_address},
        action: %{
          api_url: "/api/admin/moderators",
          api_method: "post",
          type: "adminModerators.add",
          obj: %{
            usernames: [user.username],
            board_id: board.id
          }
        }
      }

      {:ok, moderation_log} = ModerationLog.create(attrs)
      assert moderation_log.mod_username == attrs.mod.username
      assert moderation_log.mod_id == attrs.mod.id
      assert moderation_log.mod_ip == attrs.mod.ip
      assert moderation_log.action_api_url == attrs.action.api_url
      assert moderation_log.action_api_method == attrs.action.api_method
      assert moderation_log.action_type == attrs.action.type
    end
  end

  describe "page/1, action types" do
    @tag authenticated: :admin
    test "when action_type is 'adminBoards.updateCategories', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/all",
          api_method: "post",
          type: "adminBoards.updateCategories",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
    end

    @tag authenticated: :admin
    test "when action_type is 'adminModerators.add', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/admin/moderators",
          api_method: "post",
          type: "adminModerators.add",
          obj: %{usernames: [user.username], board_id: board.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "added user(s) '#{user.username}' to list of moderators for board '#{board.name}'"

      assert response_moderation_log["action_display_url"] ==
               "threads.data({ boardSlug: '#{board.slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminModerators.remove', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/admin/moderators",
          api_method: "delete",
          type: "adminModerators.remove",
          obj: %{usernames: [user.username], board_id: board.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "removed user(s) '#{user.username}' from list of moderators for board '#{board.name}'"

      assert response_moderation_log["action_display_url"] ==
               "threads.data({ boardSlug: '#{board.slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updateMessageReport', gets page", %{conn: conn} do
      message_report_id = 10

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updateMessageReport",
          api_method: "post",
          type: "reports.updateMessageReport",
          obj: %{status: "status", id: message_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated the status of message report to 'status'"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{message_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.createMessageReportNote', gets page", %{conn: conn} do
      message_report_id = 10

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/createMessageReportNote",
          api_method: "post",
          type: "reports.createMessageReportNote",
          obj: %{report_id: message_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "created a note on a message report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{message_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updateMessageReportNote', gets page", %{conn: conn} do
      message_report_id = 10

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updateMessageReportNote",
          api_method: "post",
          type: "reports.updateMessageReportNote",
          obj: %{report_id: message_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited their note on a message report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{message_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updatePostReport', gets page", %{conn: conn} do
      post_report_id = 20

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updatePostReport",
          api_method: "post",
          type: "reports.updatePostReport",
          obj: %{status: "status", id: post_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated the status of post report to 'status'"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{post_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.createPostReportNote', gets page", %{conn: conn} do
      post_report_id = 20

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/createPostReportNote",
          api_method: "post",
          type: "reports.createPostReportNote",
          obj: %{report_id: post_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "created a note on a post report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{post_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updatePostReportNote', gets page", %{conn: conn} do
      post_report_id = 20

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updatePostReportNote",
          api_method: "post",
          type: "reports.updatePostReportNote",
          obj: %{report_id: post_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited their note on a post report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{post_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updateUserReport', gets page", %{conn: conn} do
      user_report_id = 30

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updateUserReport",
          api_method: "post",
          type: "reports.updateUserReport",
          obj: %{status: "status", id: user_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated the status of user report to 'status'"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{user_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.createUserReportNote', gets page", %{conn: conn} do
      user_report_id = 30

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/createUserReportNote",
          api_method: "post",
          type: "reports.createUserReportNote",
          obj: %{report_id: user_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "created a note on a user report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{user_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'reports.updateUserReportNote', gets page", %{conn: conn} do
      user_report_id = 30

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/reports/updateUserReportNote",
          api_method: "post",
          type: "reports.updateUserReportNote",
          obj: %{report_id: user_report_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited their note on a user report"

      assert response_moderation_log["action_display_url"] ==
               "^.messages({ reportId: '#{user_report_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminRoles.add', gets page", %{conn: conn} do
      super_admin_role = %{id: 1, name: "Super Administrator"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/roles/add",
          api_method: "post",
          type: "adminRoles.add",
          obj: %{name: super_admin_role.name, id: super_admin_role.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "created a new role named '#{super_admin_role.name}'"

      assert response_moderation_log["action_display_url"] ==
               "admin-management.roles({ roleId: '#{super_admin_role.id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminRoles.remove', gets page", %{conn: conn} do
      super_admin_role = %{id: 1, name: "Super Administrator"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/roles/remove",
          api_method: "delete",
          type: "adminRoles.remove",
          obj: %{name: super_admin_role.name}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "removed the role named '#{super_admin_role.name}'"

      assert response_moderation_log["action_display_url"] == "admin-management.roles"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminRoles.update', gets page", %{conn: conn} do
      super_admin_role = %{id: 1, name: "Super Administrator"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/roles/update",
          api_method: "post",
          type: "adminRoles.update",
          obj: %{name: super_admin_role.name, id: super_admin_role.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated the role named '#{super_admin_role.name}'"

      assert response_moderation_log["action_display_url"] ==
               "admin-management.roles({ roleId: '#{super_admin_role.id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminRoles.reprioritize', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/roles/reprioritize",
          api_method: "get",
          type: "adminRoles.reprioritize",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "reordered role priorities"
      assert response_moderation_log["action_display_url"] == "admin-management.roles"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.update', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/update",
          api_method: "post",
          type: "adminSettings.update",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "updated forum settings"
      assert response_moderation_log["action_display_url"] == "admin-settings"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.addToBlacklist', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/addToBlacklist",
          api_method: "post",
          type: "adminSettings.addToBlacklist",
          obj: %{note: "note"}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "added ip blacklist rule named 'note'"

      assert response_moderation_log["action_display_url"] == "admin-settings.advanced"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.updateBlacklist', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/updateBlacklist",
          api_method: "post",
          type: "adminSettings.updateBlacklist",
          obj: %{note: "note"}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated ip blacklist rule named 'note'"

      assert response_moderation_log["action_display_url"] == "admin-settings.advanced"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.deleteFromBlacklist', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/deleteFromBlacklist",
          api_method: "delete",
          type: "adminSettings.deleteFromBlacklist",
          obj: %{note: "note"}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted ip blacklist rule named 'note'"

      assert response_moderation_log["action_display_url"] == "admin-settings.advanced"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.setTheme', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/setTheme",
          api_method: "post",
          type: "adminSettings.setTheme",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "updated the forum theme"
      assert response_moderation_log["action_display_url"] == "admin-settings.theme"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminSettings.resetTheme', gets page", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/resetTheme",
          api_method: "post",
          type: "adminSettings.resetTheme",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "restored the forum to the default theme"

      assert response_moderation_log["action_display_url"] == "admin-settings.theme"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminUsers.addRoles', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      super_admin_role = %{id: 1, name: "Super Administrator"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/addRoles",
          api_method: "post",
          type: "adminUsers.addRoles",
          obj: %{usernames: [user.username], role_id: super_admin_role.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "added role '#{super_admin_role.name}' to users(s) '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "admin-management.roles({ roleId: '#{super_admin_role.id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'adminUsers.removeRoles', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      super_admin_role = %{id: 1, name: "Super Administrator"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/removeRoles",
          api_method: "delete",
          type: "adminUsers.removeRoles",
          obj: %{role_id: super_admin_role.id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "removed role '#{super_admin_role.name}' from user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "admin-management.roles({ roleId: '#{super_admin_role.id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'userNotes.create', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/userNotes/create",
          api_method: "post",
          type: "userNotes.create",
          obj: %{user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "created a moderation note for user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'userNotes.update', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/userNotes/update",
          api_method: "post",
          type: "userNotes.update",
          obj: %{user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited their moderation note for user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'userNotes.delete', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/userNotes/delete",
          api_method: "delete",
          type: "userNotes.delete",
          obj: %{user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted their moderation note for user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.addAddresses', gets page", %{conn: conn} do
      hostname = nil
      banned_address = "127.0.0.1"

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/addAddresses",
          api_method: "post",
          type: "bans.addAddresses",
          obj: %{addresses: [%{hostname: hostname, ip: banned_address}]}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log, stringify: [:addresses])

      assert response_moderation_log["action_display_text"] ==
               "banned the following addresses '#{banned_address}'"

      assert response_moderation_log["action_display_url"] == "admin-management.banned-addresses"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.editAddress', gets page", %{conn: conn} do
      hostname = nil
      banned_address = "127.0.0.1"
      weight = 99
      decay = nil

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/editAddress",
          api_method: "post",
          type: "bans.editAddress",
          obj: %{hostname: hostname, ip: banned_address, weight: weight, decay: decay}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited banned address '#{banned_address}' to 'not decay' with a weight of '#{weight}'"

      assert response_moderation_log["action_display_url"] ==
               "admin-management.banned-addresses({ search: '#{banned_address}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.deleteAddress', gets page", %{conn: conn} do
      hostname = nil
      banned_address = "127.0.0.1"

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/deleteAddress",
          api_method: "delete",
          type: "bans.deleteAddress",
          obj: %{hostname: hostname, ip: banned_address}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted banned address '#{banned_address}'"

      assert response_moderation_log["action_display_url"] == "admin-management.banned-addresses"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.ban', gets page", %{conn: conn, users: %{user: user}} do
      ban_expiration_input = ~N[2030-12-31 00:00:00.000]
      ban_expiration_output = "31 Dec 2030"

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/ban",
          api_method: "post",
          type: "bans.ban",
          obj: %{expiration: ban_expiration_input, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log, convert_date: [:expiration])

      assert response_moderation_log["action_display_text"] ==
               "temporarily banned user '#{user.username}' until '#{ban_expiration_output}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.unban', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/unban",
          api_method: "post",
          type: "bans.unban",
          obj: %{user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
      assert response_moderation_log["action_display_text"] == "unbanned user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.banFromBoards', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/banFromBoards",
          api_method: "post",
          type: "bans.banFromBoards",
          obj: %{board_ids: [board.id], user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "banned user '#{user.username}' from boards: #{board.name}'"

      assert response_moderation_log["action_display_url"] == "^.board-bans"
    end

    @tag authenticated: :admin
    test "when action_type is 'bans.unbanFromBoards', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/bans/unbanFromBoards",
          api_method: "post",
          type: "bans.unbanFromBoards",
          obj: %{board_ids: [board.id], user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "unbanned user '#{user.username}' from boards: #{board.name}'"

      assert response_moderation_log["action_display_url"] == "^.board-bans"
    end

    @tag authenticated: :admin
    test "when action_type is 'boards.create', gets page", %{conn: conn} do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/create",
          api_method: "post",
          type: "boards.create",
          obj: %{boards: [%{name: board.name}]}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log, stringify: [:boards])

      assert response_moderation_log["action_display_text"] ==
               "created board named '#{board.name}'"

      assert response_moderation_log["action_display_url"] == "admin-management.boards"
    end

    @tag authenticated: :admin
    test "when action_type is 'boards.update', gets page", %{conn: conn} do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/update",
          api_method: "post",
          type: "boards.update",
          obj: %{boards: [%{name: board.name}]}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log, stringify: [:boards])

      assert response_moderation_log["action_display_text"] ==
               "updated board named '#{board.name}'"

      assert response_moderation_log["action_display_url"] == "admin-management.boards"
    end

    @tag authenticated: :admin
    test "when action_type is 'boards.delete', gets page", %{conn: conn} do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/delete",
          api_method: "delete",
          type: "boards.delete",
          obj: %{names: board.name}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted board named '#{board.name}'"

      assert response_moderation_log["action_display_url"] == "admin-management.boards"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.title', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_slug = thread.attributes["slug"]
      new_thread = %{title: "New Thread"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/title",
          api_method: "post",
          type: "threads.title",
          obj: %{thread_id: thread_id, user_id: user.id, title: new_thread.title}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated the title of a thread created by user '#{user.username}' to '#{new_thread.title}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.lock', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/lock",
          api_method: "post",
          type: "threads.lock",
          obj: %{locked: true, user_id: user.id, thread_id: thread_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "'locked' the thread '#{thread_title}' created by user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.sticky', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/sticky",
          api_method: "post",
          type: "threads.sticky",
          obj: %{stickied: true, thread_id: thread_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "'stickied' the thread '#{thread_title}' created by user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.move', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]
      old_board = %{name: "Old Board", slug: "old-board"}

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/move",
          api_method: "post",
          type: "threads.move",
          obj: %{
            title: thread_title,
            thread_id: thread_id,
            user_id: user.id,
            old_board_name: old_board.name,
            new_board_id: board.id
          }
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "moved the thread '#{thread_title}' created by user '#{user.username}' from board '#{old_board.name}' to '#{board.name}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.purge', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_title = thread.post.content["title"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/purge",
          api_method: "post",
          type: "threads.purge",
          obj: %{
            title: thread_title,
            user_id: user.id,
            board_name: board.name
          }
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "purged thread '#{thread_title}' created by user '#{user.username}' from board '#{board.name}'"

      assert response_moderation_log["action_display_url"] == nil
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.editPoll', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/editPoll",
          api_method: "post",
          type: "threads.editPoll",
          obj: %{thread_id: thread_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "edited a poll in thread named '#{thread_title}' created by user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.createPoll', gets page", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/createPoll",
          api_method: "post",
          type: "threads.createPoll",
          obj: %{thread_id: thread_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "created a poll in thread named '#{thread_title}' created by user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'threads.lockPoll', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/threads/lockPoll",
          api_method: "post",
          type: "threads.lockPoll",
          obj: %{locked: false, thread_id: thread_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "'unlocked' poll in thread named '#{thread_title}' created by user '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'posts.update', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]
      post_id = thread.post.id

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/posts/update",
          api_method: "post",
          type: "posts.update",
          obj: %{id: post_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "updated post created by user '#{user.username}' in thread named '#{thread_title}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}', start: '1', '#': '#{post_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'posts.delete', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]
      post_id = thread.post.id

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/posts/delete",
          api_method: "delete",
          type: "posts.delete",
          obj: %{id: post_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "hid post created by user '#{user.username}' in thread '#{thread_title}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}', start: '1', '#': '#{post_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'posts.undelete', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]
      post_id = thread.post.id

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/posts/undelete",
          api_method: "post",
          type: "posts.undelete",
          obj: %{id: post_id, user_id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "unhid post created by user '#{user.username}' in thread '#{thread_title}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}', start: '1', '#': '#{post_id}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'posts.purge', gets page", %{conn: conn, users: %{user: user}} do
      board = build(:board)
      thread = build(:thread, board: board, user: user)
      thread_id = thread.post.thread_id
      thread_title = thread.post.content["title"]
      thread_slug = thread.attributes["slug"]

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/posts/purge",
          api_method: "post",
          type: "posts.purge",
          obj: %{user_id: user.id, thread_id: thread_id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "purged post created by user '#{user.username}' in thread '#{thread_title}'"

      assert response_moderation_log["action_display_url"] ==
               "posts.data({ slug: '#{thread_slug}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'users.update', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/update",
          api_method: "post",
          type: "users.update",
          obj: %{username: user.username}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "Updated user account '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'users.deactivate', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/deactivate",
          api_method: "post",
          type: "users.deactivate",
          obj: %{id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deactivated user account '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'users.reactivate', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/reactivate",
          api_method: "post",
          type: "users.reactivate",
          obj: %{id: user.id}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "reactivated user account '#{user.username}'"

      assert response_moderation_log["action_display_url"] ==
               "profile({ username: '#{user.username}' })"
    end

    @tag authenticated: :admin
    test "when action_type is 'users.delete', gets page", %{conn: conn, users: %{user: user}} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/users/delete",
          api_method: "delete",
          type: "users.delete",
          obj: %{username: user.username}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "purged user account '#{user.username}'"

      assert response_moderation_log["action_display_url"] == nil
    end

    @tag authenticated: :admin
    test "when action_type is 'conversations.delete', gets page", %{
      conn: conn,
      users: %{user: user, admin_user: admin_user}
    } do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/conversations/delete",
          api_method: "delete",
          type: "conversations.delete",
          obj: %{
            sender_id: admin_user.id,
            receiver_ids: [user.id]
          }
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted conversation between users '#{admin_user.username}' and '#{user.username}'"

      assert response_moderation_log["action_display_url"] == nil
    end

    @tag authenticated: :admin
    test "when action_type is 'messages.delete', gets page", %{
      conn: conn,
      users: %{user: user, admin_user: admin_user}
    } do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/messages/delete",
          api_method: "delete",
          type: "messages.delete",
          obj: %{
            sender_id: admin_user.id,
            receiver_ids: [user.id]
          }
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)

      assert response_moderation_log["action_display_text"] ==
               "deleted message sent between users '#{admin_user.username}' and '#{user.username}'"

      assert response_moderation_log["action_display_url"] == nil
    end
  end

  describe "page/1, mod_id" do
    @tag authenticated: :admin
    test "given a valid id for 'mod', returns correct moderation_log entry", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/all",
          api_method: "post",
          type: "adminBoards.updateCategories",
          obj: %{}
        })

      response_moderation_log = conn |> page_response(%{"mod" => factory_moderation_log.mod_id})

      assert compare(response_moderation_log, factory_moderation_log)
    end

    @tag authenticated: :admin
    test "given an invalid id for 'mod', returns an empty list", %{conn: conn} do
      invalid_mod_id = 0
      assert conn |> page_response_list(%{"mod" => invalid_mod_id}) |> Enum.empty?() == true
    end
  end

  describe "page/1, mod_username" do
    @tag authenticated: :admin
    test "given a valid username for 'mod', returns correct moderation_log entry", %{conn: conn} do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/boards/all",
          api_method: "post",
          type: "adminBoards.updateCategories",
          obj: %{}
        })

      response_moderation_log =
        conn |> page_response(%{"mod" => factory_moderation_log.mod_username})

      assert compare(response_moderation_log, factory_moderation_log)
    end

    @tag authenticated: :admin
    test "given an invalid string for 'mod', returns an empty list", %{conn: conn} do
      invalid_mod_username = ""
      assert conn |> page_response_list(%{"mod" => invalid_mod_username}) |> Enum.empty?() == true
    end
  end

  describe "page/1, action_type" do
    @tag authenticated: :admin
    test "given a valid action_type 'action', returns correct moderation_log entry", %{
      conn: conn,
      users: %{user: user}
    } do
      board = build(:board)

      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/admin/moderators",
          api_method: "delete",
          type: "adminModerators.remove",
          obj: %{usernames: [user.username], board_id: board.id}
        })

      response_moderation_log =
        conn |> page_response(%{"action" => factory_moderation_log.action_type})

      assert compare(response_moderation_log, factory_moderation_log)
    end

    @tag authenticated: :admin
    test "given an unpopulated action_type 'action', returns an empty list", %{conn: conn} do
      unpopulated_action_type = "adminBoards.updateCategories"

      assert conn |> page_response_list(%{"action" => unpopulated_action_type}) |> Enum.empty?() ==
               true
    end

    @tag authenticated: :admin
    test "given an invalid action_type 'action', returns an empty list", %{conn: conn} do
      invalid_action_type = ""

      assert_raise Postgrex.Error, fn ->
        conn |> page_response_list(%{"action" => invalid_action_type})
      end
    end
  end

  describe "page/1, action_display_text" do
    @tag authenticated: :admin
    test "given a valid action_display_text 'keyword', returns correct moderation_log entry", %{
      conn: conn
    } do
      factory_moderation_log =
        build(:moderation_log, %{
          api_url: "/api/settings/setTheme",
          api_method: "post",
          type: "adminSettings.setTheme",
          obj: %{}
        })

      response_moderation_log =
        conn |> page_response(%{"keyword" => factory_moderation_log.action_display_text})

      assert compare(response_moderation_log, factory_moderation_log)
    end

    @tag authenticated: :admin
    test "given an invalid 'keyword', returns an empty list", %{conn: conn} do
      invalid_keyword = ""
      assert conn |> page_response_list(%{"keyword" => invalid_keyword}) |> Enum.empty?() == true
    end
  end

  describe "page/1, by date" do
    setup do
      number_of_logs = 58

      logs =
        build_list(number_of_logs, :moderation_log, %{
          api_url: "/api/settings/setTheme",
          api_method: "post",
          type: "adminSettings.setTheme",
          obj: %{}
        })

      {:ok, logs: logs, number_of_logs: number_of_logs}
    end

    @tag authenticated: :admin
    test "given a future 'before date', returns correct moderation_log entries", %{
      conn: conn,
      number_of_logs: number_of_logs
    } do
      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "bdate" => List.first(String.split(two_days_from_now)),
          "page" => 1,
          "limit" => 100
        })

      assert length(response_moderation_log) == number_of_logs
    end

    @tag authenticated: :admin
    test "given a past 'before date', returns an empty list", %{conn: conn} do
      two_days_ago = NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "bdate" => List.first(String.split(two_days_ago))
        })

      assert Enum.empty?(response_moderation_log) == true
    end

    @tag authenticated: :admin
    test "given a past 'after date', returns correct moderation_log entries", %{conn: conn} do
      two_days_ago = NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "adate" => List.first(String.split(two_days_ago)),
          "page" => 1,
          "limit" => 100
        })

      assert length(response_moderation_log) == 58
    end

    @tag authenticated: :admin
    test "given a future 'after date', returns an empty list", %{conn: conn} do
      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "adate" => List.first(String.split(two_days_from_now))
        })

      assert Enum.empty?(response_moderation_log) == true
    end

    @tag authenticated: :admin
    test "given a valid date range, returns correct moderation_log entries", %{conn: conn} do
      two_days_ago = NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day))

      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "sdate" => List.first(String.split(two_days_ago)),
          "edate" => List.first(String.split(two_days_from_now)),
          "page" => 1,
          "limit" => 100
        })

      assert length(response_moderation_log) == 58
    end

    @tag authenticated: :admin
    test "given an invalid date range, returns an empty list", %{conn: conn} do
      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      four_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 4, :day))

      response_moderation_log =
        conn
        |> page_response_list(%{
          "sdate" => List.first(String.split(two_days_from_now)),
          "edate" => List.first(String.split(four_days_from_now))
        })

      assert Enum.empty?(response_moderation_log) == true
    end

    @tag authenticated: :admin
    test "given an valid id and date range, returns correct moderation_log", %{
      conn: conn,
      logs: logs
    } do
      two_days_ago = NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day))

      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      first_log = List.first(logs)

      response_moderation_log =
        conn
        |> page_response_list(%{
          "mod" => first_log.mod_id,
          "sdate" => List.first(String.split(two_days_ago)),
          "edate" => List.first(String.split(two_days_from_now))
        })

      assert List.first(response_moderation_log)["mod_id"] == first_log.mod_id
    end

    @tag authenticated: :admin
    test "given a valid username and date range, returns correct moderation_log", %{
      conn: conn,
      logs: logs
    } do
      two_days_ago = NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day))

      two_days_from_now =
        NaiveDateTime.to_string(NaiveDateTime.add(NaiveDateTime.utc_now(), 2, :day))

      first_log = List.first(logs)

      response_moderation_log =
        conn
        |> page_response_list(%{
          "mod" => first_log.mod_username,
          "sdate" => List.first(String.split(two_days_ago)),
          "edate" => List.first(String.split(two_days_from_now))
        })

      assert List.first(response_moderation_log)["mod_username"] == first_log.mod_username
    end
  end
end
