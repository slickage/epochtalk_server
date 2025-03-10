defmodule EpochtalkServer.SmfQuery do
  import Ecto.Query
  alias EpochtalkServer.SmfRepo
  alias EpochtalkServerWeb.Helpers.ProxyPagination

  @default_page 1
  @default_per_page 25
  @ms_per_sec 1000

  @moduledoc """
  Helper for pulling and formatting data from SmfRepo
  """

  defp extract_opts(opts) do
    default_opts = %{
      page: @default_page,
      per_page: @default_per_page,
      desc: false
    }

    Enum.into(opts, default_opts)
  end

  def find_user(user_id) do
    from(u in "smf_members", where: u.id_member == ^user_id)
    |> join(:left, [u], a in "smf_attachments",
      on: u.id_member == a.id_member and a.attachmentType == 1
    )
    |> join(:left, [u], m in "smf_membergroups", on: u.id_group != 0 and u.id_group == m.id_group)
    |> join(:left, [u], g in "smf_membergroups", on: u.id_post_group == g.id_group)
    |> select([u, a, m, g], %{
      activity: u.activity,
      created_at: u.dateRegistered * 1000,
      dob: u.birthdate,
      gender: u.gender,
      id: u.id_member,
      language: nil,
      location: u.location,
      merit: u.merit,
      id_group: u.id_group,
      id_post_group: u.id_post_group,
      signature: u.signature,
      post_count: u.posts,
      name: u.realName,
      username: u.realName,
      title: u.usertitle,
      website: u.websiteUrl,
      last_login: u.lastLogin * 1000,
      show_online: u.showOnline,
      group_name: m.groupName,
      group_name_2: g.groupName,
      group_color: m.onlineColor,
      group_color_2: g.onlineColor,
      avatar:
        fragment(
          "if(? <>'',concat('https://bitcointalk.org/avatars/',?),ifnull(concat('https://bitcointalk.org/useravatars/',?),''))",
          u.avatar,
          u.avatar,
          a.filename
        )
    })
    |> SmfRepo.one()
  end

  def poll_by_thread(thread_id) do
    from(t in "smf_topics",
      where: t.id_topic == ^thread_id
    )
    |> join(:left, [t], p in "smf_polls", on: t.id_poll == p.id_poll)
    |> select([t, p], %{
      id: t.id_poll,
      change_vote: p.changeVote,
      display_mode: "always",
      expiration: p.expireTime * @ms_per_sec,
      has_voted: false,
      locked: p.votingLocked == 1,
      max_answers: p.maxVotes,
      question: p.question
    })
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Poll for thread not found"}

      poll ->
        from(t in "smf_topics",
          where: t.id_topic == ^thread_id
        )
        |> join(:left, [t], pc in "smf_poll_choices", on: t.id_poll == pc.id_poll)
        |> select([t, pc], %{
          id: pc.id_choice,
          selected: false,
          votes: pc.votes,
          answer: pc.label
        })
        |> SmfRepo.all()
        |> case do
          [] ->
            {:error, "Poll for thread not found"}

          answers ->
            if poll.id > 0, do: Map.put(poll, :answers, answers), else: nil
        end
    end
  end

  def recent_threads() do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(t in "smf_topics",
      limit: 5,
      where: t.id_board not in ^id_board_blacklist,
      order_by: [desc: t.id_last_msg]
    )
    |> join(:left, [t], f in "smf_messages", on: t.id_first_msg == f.id_msg)
    |> join(:left, [t, f], l in "smf_messages", on: t.id_last_msg == l.id_msg)
    |> join(:left, [t, f, l], lm in "smf_members", on: l.id_member == lm.id_member)
    |> join(:left, [t, f, l, lm], b in "smf_boards", on: t.id_board == b.id_board)
    |> select([t, f, l, lm, b], %{
      id: t.id_topic,
      slug: t.id_topic,
      board_id: t.id_board,
      board_name: b.name,
      board_slug: t.id_board,
      sticky: t.isSticky,
      locked: t.locked,
      poll: t.id_poll > 0,
      moderated: t.selfModerated,
      first_post_id: t.id_first_msg,
      last_post_id: t.id_last_msg,
      title: f.subject,
      updated_at: l.posterTime * @ms_per_sec,
      last_post_created_at: l.posterTime * @ms_per_sec,
      last_post_user_id: l.id_member,
      last_post_username: lm.realName,
      view_count: t.numViews,
      last_post_position: nil,
      last_post_deleted: false,
      last_post_user_deleted: false,
      new_post_id: nil,
      new_post_position: nil,
      is_proxy: true
    })
    |> SmfRepo.all()
    |> case do
      [] ->
        {:error, "Recent threads not found"}

      threads ->
        threads
    end
  end

  def category(id) do
    from(c in "smf_categories",
      where: c.id_cat == ^id,
      select: %{
        id: c.id_cat,
        name: c.name,
        view_order: c.catOrder
      }
    )
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Category not found for id: #{id}"}

      category ->
        category
    end
  end

  def board_counts() do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(b in "smf_boards",
      where: b.id_board not in ^id_board_blacklist,
      select: %{
        id: b.id_board,
        thread_count: b.numTopics,
        post_count: b.numPosts
      }
    )
    |> SmfRepo.all()
    |> case do
      [] ->
        {:error, "Boards not found"}

      boards ->
        return_tuple(boards)
    end
  end

  def board_last_post_info() do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(b in "smf_boards",
      where: b.id_board not in ^id_board_blacklist
    )
    |> join(:left, [b], m in "smf_messages", on: b.id_last_msg == m.id_msg)
    |> join(:left, [b, m], t in "smf_topics", on: m.id_topic == t.id_topic)
    |> join(:left, [b, m, t], u in "smf_members", on: m.id_member == u.id_member)
    |> join(:left, [b, m, t, u], a in "smf_attachments",
      on: m.id_member == a.id_member and a.attachmentType == 1
    )
    |> select([b, m, t, u, a], %{
      id: b.id_board,
      last_post_created_at: m.posterTime * @ms_per_sec,
      last_post_position: t.numReplies,
      last_post_username: u.realName,
      last_post_user_id: m.id_member,
      last_post_avatar:
        fragment(
          "if(? <>'',concat('https://bitcointalk.org/avatars/',?),ifnull(concat('https://bitcointalk.org/useravatars/',?),''))",
          u.avatar,
          u.avatar,
          a.filename
        ),
      last_thread_created_at: t.id_member_started,
      last_thread_id: t.id_topic,
      last_thread_post_count: t.numReplies,
      last_thread_slug: t.id_topic,
      last_thread_title: m.subject,
      last_thread_updated_at: m.posterTime * @ms_per_sec
    })
    |> SmfRepo.all()
    |> case do
      [] ->
        {:error, "Boards not found"}

      boards ->
        return_tuple(boards)
    end
  end

  def board_moderators() do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(b in "smf_boards",
      where: b.id_board not in ^id_board_blacklist
    )
    |> join(:inner, [b], mod in "smf_moderators", on: b.id_board == mod.id_board)
    |> join(:inner, [b, mod], m in "smf_members", on: mod.id_member == m.id_member)
    |> select([b, mod, m], %{
      board_id: b.id_board,
      user_id: m.id_member,
      user: %{
        username: m.realname
      }
    })
    |> SmfRepo.all()
    |> case do
      [] ->
        {:error, "Board Moderators not found"}

      moderators ->
        return_tuple(moderators)
    end
  end

  def board(id) do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(b in "smf_boards",
      where: b.id_board == ^id and b.id_board not in ^id_board_blacklist,
      select: %{
        id: b.id_board,
        slug: b.id_board,
        cat_id: b.id_cat,
        name: b.name,
        description: b.description,
        thread_count: b.numTopics,
        post_count: b.numPosts
      }
    )
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Board not found for id: #{id}"}

      board ->
        board
    end
  end

  def threads_by_board(id, opts) do
    %{
      page: page,
      per_page: per_page,
      desc: desc,
      field: field
    } = extract_opts(opts)

    # map field
    field_map = %{
      "updated_at" => "id_last_msg",
      "post_count" => "numReplies",
      "views" => "numViews"
    }

    sort_field = field_map[field]
    direction = if desc, do: :desc, else: :asc

    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    count_query =
      from t in "smf_topics",
        where: t.id_board == ^id and t.id_board not in ^id_board_blacklist,
        select: %{count: count(t.id_topic)}

    from(t in "smf_topics",
      where: t.id_board == ^id and t.id_board not in ^id_board_blacklist,
      order_by: [{^direction, field(t, ^:"#{sort_field}")}]
    )
    |> join(:left, [t], f in "smf_messages", on: t.id_first_msg == f.id_msg)
    |> join(:left, [t, f], fm in "smf_members", on: f.id_member == fm.id_member)
    |> join(:left, [t, f, fm], l in "smf_messages", on: t.id_last_msg == l.id_msg)
    |> join(:left, [t, f, fm, l], lm in "smf_members", on: l.id_member == lm.id_member)
    |> join(:left, [t, f, fm, l, lm], a in "smf_attachments",
      on: lm.id_member == a.id_member and a.attachmentType == 1
    )
    |> select([t, f, fm, l, lm, a], %{
      id: t.id_topic,
      slug: t.id_topic,
      board_id: t.id_board,
      sticky: t.isSticky,
      locked: t.locked,
      view_count: t.numViews,
      first_post_id: t.id_first_msg,
      last_post_id: t.id_last_msg,
      started_user_id: t.id_member_started,
      last_post_user_id: t.id_member_updated,
      moderated: t.selfModerated,
      post_count: t.numReplies,
      title: f.subject,
      user_id: f.id_member,
      username: fm.realName,
      created_at: f.posterTime * @ms_per_sec,
      user_deleted: false,
      last_post_created_at: l.posterTime * @ms_per_sec,
      last_post_deleted: false,
      last_post_user_id: l.id_member,
      last_post_username: lm.realName,
      last_post_user_deleted: false,
      last_post_avatar:
        fragment(
          "if(? <>'',concat('https://bitcointalk.org/avatars/',?),ifnull(concat('https://bitcointalk.org/useravatars/',?),''))",
          lm.avatar,
          lm.avatar,
          a.filename
        ),
      last_viewed: nil,
      is_proxy: true
    })
    |> ProxyPagination.page_simple(count_query, page, per_page: per_page, desc: desc)
  end

  def thread(id) do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(t in "smf_topics",
      where: t.id_topic == ^id and t.id_board not in ^id_board_blacklist
    )
    # get first and last message for thread
    |> join(:left, [t], f in "smf_messages", on: t.id_first_msg == f.id_msg)
    |> join(:left, [t, f], fm in "smf_members", on: f.id_member == fm.id_member)
    |> join(:left, [t, f, fm], l in "smf_messages", on: t.id_last_msg == l.id_msg)
    |> join(:left, [t, f, fm, l], lm in "smf_members", on: l.id_member == lm.id_member)
    |> select([t, f, fm, l, lm], %{
      id: t.id_topic,
      slug: t.id_topic,
      board_id: t.id_board,
      sticky: t.isSticky,
      locked: t.locked,
      view_count: t.numViews,
      first_post_id: t.id_first_msg,
      last_post_id: t.id_last_msg,
      started_user_id: t.id_member_started,
      updated_user_id: t.id_member_updated,
      moderated: t.selfModerated,
      post_count: t.numReplies,
      title: f.subject,
      user_id: f.id_member,
      username: fm.realName,
      created_at: f.posterTime * @ms_per_sec,
      user_deleted: false,
      last_post_created_at: l.posterTime * @ms_per_sec,
      last_post_deleted: false,
      last_post_user_id: l.id_member,
      last_post_username: lm.realName,
      last_post_user_deleted: false,
      last_viewed: nil
    })
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Thread not found for id: #{id}"}

      thread ->
        thread
    end
  end

  def post(id) do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    from(m in "smf_messages",
      where: m.id_msg == ^id and m.id_board not in ^id_board_blacklist,
      select: %{
        id: m.id_msg,
        thread_id: m.id_topic,
        board_id: m.id_board,
        user_id: m.id_member,
        title: m.subject,
        body: m.body,
        updated_at: m.modifiedTime
      }
    )
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Post not found for id: #{id}"}

      post ->
        post
    end
  end

  def post_page(id, thread_id, limit) do
    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    # count how many post there are with ids less than or equal to the post were trying to locate
    from(m in "smf_messages",
      where:
        m.id_topic == ^thread_id and m.id_msg <= ^id and m.id_board not in ^id_board_blacklist,
      select: %{
        position: count(m.id_msg)
      }
    )
    |> SmfRepo.one()
    |> case do
      [] ->
        {:error, "Post not found for id: #{id}"}

      # page = ceil ( postPos / limit )
      post ->
        ceil(post.position / limit)
    end
  end

  def posts_by_thread(id, opts) do
    %{
      page: page,
      per_page: per_page
    } = extract_opts(opts)

    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    count_query =
      from m in "smf_messages",
        where: m.id_topic == ^id and m.id_board not in ^id_board_blacklist,
        select: %{count: count(m.id_topic)}

    from(m in "smf_messages",
      limit: ^per_page,
      where: m.id_topic == ^id and m.id_board not in ^id_board_blacklist,
      order_by: [asc: m.id_msg]
    )
    |> join(:left, [m], u in "smf_members", on: m.id_member == u.id_member)
    |> join(:left, [m, u], a in "smf_attachments",
      on: u.id_member == a.id_member and a.attachmentType == 1
    )
    |> select([m, u, a], %{
      id: m.id_msg,
      thread_id: m.id_topic,
      board_id: m.id_board,
      title: m.subject,
      body: m.body,
      updated_at: m.modifiedTime,
      username: u.realName,
      created_at: m.posterTime * @ms_per_sec,
      modified_time: m.modifiedTime,
      avatar:
        fragment(
          "if(? <>'',concat('https://bitcointalk.org/avatars/',?),ifnull(concat('https://bitcointalk.org/useravatars/',?),''))",
          u.avatar,
          u.avatar,
          a.filename
        ),
      user: %{
        id: m.id_member,
        username: u.realName,
        activity: u.activity,
        merit: u.merit,
        title: u.usertitle
      }
    })
    |> ProxyPagination.page_simple(count_query, page, per_page: per_page, desc: true)
    |> case do
      {:ok, [], _} ->
        {:error, "Posts not found for thread_id: #{id}"}

      {:error, :page_does_not_exist} ->
        {:error, :page_does_not_exist}

      {:ok, posts, data} ->
        return_tuple(posts, data)
    end
  end

  def posts_by_user(id, opts) do
    %{
      page: page,
      per_page: per_page,
      desc: desc
    } = extract_opts(opts)

    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    direction = if desc, do: :desc, else: :asc

    count_query =
      from m in "smf_messages",
        where: m.id_member == ^id and m.id_board not in ^id_board_blacklist,
        select: %{count: count(m.id_msg)}

    from(m in "smf_messages",
      limit: ^per_page,
      where: m.id_member == ^id and m.id_board not in ^id_board_blacklist,
      order_by: [{^direction, m.id_msg}]
    )
    |> select([m], %{
      id: m.id_msg,
      thread_id: m.id_topic,
      board_id: m.id_board,
      thread_title: m.subject,
      thread_slug: m.id_topic,
      position: 0,
      body_html: m.body,
      updated_at: m.modifiedTime,
      created_at: m.posterTime * 1000,
      user: %{
        id: m.id_member
      }
    })
    |> ProxyPagination.page_simple(count_query, page, per_page: per_page, desc: desc)
  end

  def threads_by_user(id, opts) do
    %{
      page: page,
      per_page: per_page,
      desc: desc
    } = extract_opts(opts)

    %{id_board_blacklist: id_board_blacklist} =
      Application.get_env(:epochtalk_server, :proxy_config)

    direction = if desc, do: :desc, else: :asc

    from(t in "smf_topics",
      where: t.id_member_started == ^id and t.id_board not in ^id_board_blacklist,
      order_by: [{^direction, t.id_topic}]
    )
    |> join(:left, [t], f in "smf_messages", on: t.id_first_msg == f.id_msg)
    |> join(:left, [t], l in "smf_messages", on: t.id_last_msg == l.id_msg)
    |> select([t, f, l], %{
      thread_id: t.id_topic,
      thread_slug: t.id_topic,
      board_id: t.id_board,
      sticky: t.isSticky,
      locked: t.locked,
      user: %{id: t.id_member_started, deleted: false},
      moderated: t.selfModerated,
      post_count: t.numReplies,
      thread_title: f.subject,
      body: f.body,
      created_at: f.posterTime * 1000,
      updated_at: l.posterTime * 1000,
      board_visible: true,
      is_proxy: true
    })
    |> ProxyPagination.page_next_prev(page, per_page: per_page, desc: desc)
  end

  defp return_tuple(object) do
    if length(object) > 1 do
      {:ok, object}
    else
      {:ok, List.first(object)}
    end
  end

  defp return_tuple(object, data) do
    if length(object) > 1 do
      {:ok, object, data}
    else
      {:ok, List.first(object), data}
    end
  end
end
