defmodule EpochtalkServerWeb.Controllers.PostJSON do
  alias EpochtalkServerWeb.Controllers.BoardJSON
  alias EpochtalkServerWeb.Controllers.ThreadJSON
  alias EpochtalkServerWeb.Helpers.ACL
  require Logger

  @moduledoc """
  Renders and formats `Post` data, in JSON format for frontend
  """

  @doc """
  Renders `Post` data after creating new `Post`
  """
  def create(%{
        post_data: post_data
      }) do
    post_data
  end

  @doc """
  Renders `Post` data after updating existing `Post`
  """
  def update(%{
        post_data: post_data
      }) do
    post_data
  end

  @doc """
  Renders `Post` data for preview purposes

    ## Example
    iex> parsed_body = %{parsed_body: "<p><strong>Hello World</strong><p>"}
    iex> EpochtalkServerWeb.Controllers.PostJSON.preview(parsed_body)
    parsed_body
  """
  def preview(%{
        parsed_body: parsed_body
      }) do
    %{parsed_body: parsed_body}
  end

  @doc """
  Renders `Post` page data for posts linked from quote headers
  """
  def page(%{
        page: page,
        post_id: post_id
      }) do
    %{page: page, post_id: post_id}
  end

  @doc """
  Renders `Post` data for parsed legacy `Post` data

    ## Example
    iex> parsed_body = %{parsed_body: "<p><strong>Hello World</strong><p>"}
    iex> EpochtalkServerWeb.Controllers.PostJSON.preview(parsed_body)
    parsed_body
  """
  def parse_legacy(%{
        parsed_body: parsed_body
      }) do
    %{parsed_body: parsed_body}
  end

  @doc """
  Renders all `Post` for a particular `Thread`.
  """
  def by_thread(%{
        posts: posts,
        poll: poll,
        thread: thread,
        write_access: write_access,
        board_banned: board_banned,
        user: user,
        user_priority: user_priority,
        board_mapping: board_mapping,
        board_moderators: board_moderators,
        page: page,
        start: start,
        limit: limit,
        desc: desc,
        metric_rank_maps: metric_rank_maps,
        ranks: ranks,
        watched: watched,
        view_deleted_posts: view_deleted_posts
      }) do
    formatted_board =
      BoardJSON.format_board_data_for_find(
        board_moderators,
        board_mapping,
        thread.board_id,
        user_priority
      )

    formatted_poll = format_poll_data_for_by_thread(poll, user)

    formatted_thread =
      thread
      |> ThreadJSON.format_user_data()
      |> Map.put(:poll, formatted_poll)
      |> Map.put(:watched, watched)

    formatted_posts =
      posts
      |> Enum.map(&format_post_data_for_by_thread(&1))
      |> handle_deleted_posts(formatted_thread, user, user_priority, view_deleted_posts)

    %{
      board: formatted_board,
      posts: formatted_posts,
      thread: formatted_thread,
      write_access: write_access,
      board_banned: board_banned,
      metadata: %{
        rank_metric_maps: metric_rank_maps,
        ranks: ranks
      },
      page: page,
      start: start,
      limit: limit,
      desc: desc
    }
  end

  def by_thread_proxy(%{
        posts: posts,
        poll: poll,
        thread: thread,
        user_priority: user_priority,
        board_mapping: board_mapping,
        board_moderators: board_moderators,
        page: page,
        limit: limit
      }) do
    # format board data
    board =
      BoardJSON.format_board_data_for_find(
        board_moderators,
        board_mapping,
        thread.board_id,
        user_priority
      )

    thread = Map.put(thread, :poll, poll)

    # convert singular post to list
    posts = if is_map(posts), do: [posts], else: posts

    # format post data
    posts =
      posts
      |> format_proxy_posts_for_by_thread_without_signature()

    # build by_thread results
    %{
      posts: posts,
      thread: thread,
      board: board,
      page: page,
      limit: limit
    }
  end

  @doc """
  Renders all `Post` for a particular `User`.
  """
  def by_username(%{
        posts: posts,
        user: user,
        priority: priority,
        view_deleted_posts: view_deleted_posts,
        count: count,
        limit: limit,
        page: page,
        desc: desc
      }) do
    posts =
      posts
      |> Enum.map(&(Map.put(&1, :body_html, &1.body) |> Map.delete(:body)))
      |> handle_deleted_posts(nil, user, priority, view_deleted_posts)

    %{
      posts: posts,
      page: page,
      desc: desc,
      limit: limit,
      count: count
    }
  end

  @doc """
  Renders all `Post` for a particular `User`.
  """
  def proxy_by_username(%{
        posts: posts,
        count: count,
        limit: limit,
        page: page,
        desc: desc
      })
      when is_list(posts) do
    posts =
      posts
      |> format_proxy_posts_for_by_thread()

    %{
      posts: posts,
      count: count,
      limit: limit,
      page: page,
      desc: desc
    }
  end

  def proxy_by_username(%{
        posts: posts,
        count: count,
        limit: limit,
        page: page,
        desc: desc
      }),
      do:
        proxy_by_username(%{
          posts: [posts],
          count: count,
          limit: limit,
          page: page,
          desc: desc
        })

  ## === Public Helper Functions ===

  def handle_deleted_posts(posts, thread, user, authed_user_priority, view_deleted_posts) do
    authed_user_id = if is_nil(user), do: nil, else: user.id

    has_self_mod_bypass =
      ACL.has_permission(user, "posts.byThread.bypass.viewDeletedPosts.selfMod")

    has_priority_bypass =
      ACL.has_permission(user, "posts.byThread.bypass.viewDeletedPosts.priority")

    has_self_mod_permissions = has_self_mod_bypass or has_priority_bypass

    authed_user_is_self_mod =
      if thread != nil,
        do: thread.user.id == authed_user_id and thread.moderated and has_self_mod_permissions,
        else: false

    viewable_in_board_with_id = if is_list(view_deleted_posts), do: view_deleted_posts

    cleaned_posts =
      posts
      |> Enum.map(
        &handle_deleted_post(
          &1,
          authed_user_id,
          authed_user_priority,
          authed_user_is_self_mod,
          view_deleted_posts,
          viewable_in_board_with_id
        )
      )

    # return posts for now
    cleaned_posts
  end

  ## === Private Helper Functions ===

  defp handle_deleted_post(
         post,
         authed_user_id,
         authed_user_priority,
         authed_user_is_self_mod,
         view_deleted_posts,
         viewable_in_board_with_id
       ) do
    # check if metadata map exists
    metadata_map_exists = !!Map.get(post, :metadata) and Map.keys(post.metadata) != []

    # get information about how current post was hidden
    post_hidden_by_priority =
      if metadata_map_exists && post.metadata["hidden_by_priority"] != nil,
        do: post.metadata["hidden_by_priority"]

    post_hidden_by_id =
      if metadata_map_exists && post.metadata["hidden_by_id"] != nil,
        do: post.metadata["hidden_by_id"],
        else: post.user.id

    # check if user has priority to view hidden post,
    # or if the user was the one who hid the post
    authed_user_has_priority =
      if is_nil(post_hidden_by_priority),
        do: false,
        else: authed_user_priority <= post_hidden_by_priority

    authed_user_hid_post = post_hidden_by_id == authed_user_id

    post_is_viewable =
      post_viewable?(
        post,
        authed_user_id,
        authed_user_is_self_mod,
        authed_user_has_priority,
        authed_user_hid_post,
        view_deleted_posts,
        viewable_in_board_with_id
      )

    # delete posts that are marked deleted, the user was deleted, or the board is not visible
    post_is_deleted = post.deleted || post.user.deleted || Map.get(post, :board_visible) == false

    # only hide deleted posts if user does not has permissions to see them
    post = maybe_delete_post_data(post, post_is_viewable, post_is_deleted)

    # return updated post
    post
  end

  defp post_viewable?(
         post,
         authed_user_id,
         authed_user_is_self_mod,
         authed_user_has_priority,
         authed_user_hid_post,
         view_deleted_posts,
         viewable_in_board_with_id
       ) do
    cond do
      # user owns the post
      authed_user_id == post.user.id ->
        true

      # user is viewing post within a board they moderate
      !!viewable_in_board_with_id and post.board_id in viewable_in_board_with_id ->
        true

      # if view_deleted_posts is true, every post is viewable
      view_deleted_posts ->
        true

      # if the authed user is a self mod of the current thread, and
      # the post is not deleted, then the post is viewable if they have
      # the appropriate priority or they are the one who hid the post
      authed_user_is_self_mod and !!post.deleted ->
        authed_user_has_priority or authed_user_hid_post

      # default to false
      true ->
        false
    end
  end

  defp maybe_delete_post_data(post, post_is_viewable, post_is_deleted) do
    post =
      cond do
        # post is deleted but user has permission to view it, hide the post
        post_is_viewable and post_is_deleted ->
          Map.put(post, :hidden, true)

        # post is deleted and user does not have permission to view it, modify and delete post
        post_is_deleted ->
          %{
            id: post.id,
            hidden: true,
            _deleted: true,
            position: post.position,
            thread_title: "deleted",
            user: %{}
          }

        # post was not marked deleted, return the original post
        true ->
          post
      end

    # remove deleted property if not set to true
    post = if Map.get(post, :deleted) != true, do: Map.delete(post, :deleted), else: post

    # remove board_visible property
    post = Map.delete(post, :board_visible)

    # remove user deleted property from nested user map
    Map.put(post, :user, Map.delete(post.user, :deleted))
  end

  defp format_poll_data_for_by_thread(nil, _), do: nil

  defp format_poll_data_for_by_thread(poll, user) do
    formatted_poll = %{
      id: poll.id,
      change_vote: poll.change_vote,
      display_mode: poll.display_mode,
      expiration: poll.expiration,
      locked: poll.locked,
      max_answers: poll.max_answers,
      question: poll.question
    }

    answers =
      Enum.map(poll.poll_answers, fn answer ->
        selected =
          if is_nil(user),
            do: false,
            else: answer.poll_responses |> Enum.filter(&(&1.user_id == user.id)) |> length() > 0

        %{
          answer: answer.answer,
          id: answer.id,
          selected: selected,
          votes: answer.poll_responses |> length()
        }
      end)

    has_voted = answers |> Enum.filter(& &1.selected) |> length() > 0

    formatted_poll
    |> Map.put(:answers, answers)
    |> Map.put(:has_voted, has_voted)
  end

  defp format_post_data_for_by_thread(post) do
    post
    # if body_html does not exist, default to post.body
    |> Map.put(:body_html, post.body_html || post.body)
    |> Map.put(:user, %{
      id: post.user_id,
      name: post.name,
      original_poster: post.original_poster,
      username: post.username,
      priority: if(is_nil(post.priority), do: post.default_priority, else: post.priority),
      deleted: post.user_deleted,
      signature: post.signature,
      post_count: post.post_count,
      highlight_color: post.highlight_color,
      role_name: post.role_name,
      stats: Map.get(post, :user_trust_stats),
      ignored: Map.get(post, :user_ignored),
      _ignored: Map.get(post, :user_ignored),
      activity: Map.get(post, :user_activity)
    })
    |> Map.delete(:user_id)
    |> Map.delete(:username)
    |> Map.delete(:priority)
    |> Map.delete(:default_priority)
    |> Map.delete(:original_poster)
    |> Map.delete(:name)
    |> Map.delete(:user_deleted)
    |> Map.delete(:post_count)
    |> Map.delete(:signature)
    |> Map.delete(:highlight_color)
    |> Map.delete(:role_name)
  end

  defp format_proxy_posts_for_by_thread_without_signature(posts) do
    # extract body/signature lists from posts
    body_list =
      posts
      |> Enum.reduce([], fn post, body_list ->
        if EpochtalkServer.Cache.ParsedPosts.need_update(post.id, post) do
          body = String.replace(Map.get(post, :body) || Map.get(post, :body_html), "'", "\'")

          # add space to end if the last character is a backslash (fix for parser)
          body_len = String.length(body)
          last_char = String.slice(body, (body_len - 1)..body_len)
          body = if last_char == "\\", do: body <> " ", else: body

          # return body list in reverse order
          [body | body_list]
        else
          [nil | body_list]
        end
      end)

    # reverse body list
    body_list = Enum.reverse(body_list)

    # parse body/signature lists
    parsed_body_list =
      body_list
      |> EpochtalkServer.BBCParser.parse_list()
      |> case do
        {:ok, parsed_list} ->
          parsed_list

        {:error, unparsed_list} ->
          Logger.error("#{__MODULE__}(list parse): #{inspect(unparsed_list)}")
          unparsed_list
      end

    zip_posts_without_signature(posts, parsed_body_list)
  end

  defp zip_posts_without_signature(posts, parsed_body_list) do
    # zip posts with body lists
    zipped_posts =
      Enum.zip_with(
        [posts, parsed_body_list],
        fn [post, parsed_body] ->
          parsed_body =
            case parsed_body do
              {:ok, parsed_body} ->
                Logger.debug("#{__MODULE__}(body): post_id #{inspect(post.id)}")
                parsed_body

              {:timeout, unparsed_body} ->
                Logger.error("#{__MODULE__}(body timeout): post_id #{inspect(post.id)}")
                unparsed_body
            end

          post =
            if parsed_body do
              # post was parsed, store it in cache
              EpochtalkServer.Cache.ParsedPosts.put(post.id, %{
                body_html: parsed_body,
                updated_at: post.updated_at
              })

              post
              |> Map.put(:body_html, parsed_body)
            else
              # post was not parsed, get value from cache
              post =
                case EpochtalkServer.Cache.ParsedPosts.get(post.id) do
                  {:ok, cached_post} ->
                    post
                    |> Map.put(:body_html, cached_post.body_html)

                  {:error, _} ->
                    nil
                end

              post
            end

          post
        end
      )

    EpochtalkServer.Cache.ParsedPosts.lookup_and_purge()
    zipped_posts
  end

  defp format_proxy_posts_for_by_thread(posts) do
    # extract body/signature lists from posts
    {body_list, signature_list} =
      posts
      |> Enum.reduce({[], []}, fn post, {body_list, signature_list} ->
        if EpochtalkServer.Cache.ParsedPosts.need_update(post.id, post) do
          body = String.replace(Map.get(post, :body) || Map.get(post, :body_html), "'", "\'")

          # add space to end if the last character is a backslash (fix for parser)
          body_len = String.length(body)
          last_char = String.slice(body, (body_len - 1)..body_len)
          body = if last_char == "\\", do: body <> " ", else: body

          signature =
            if Map.get(post.user, :signature),
              do: String.replace(post.user.signature, "'", "\'"),
              else: nil

          # return body/signature lists in reverse order
          {[body | body_list], [signature | signature_list]}
        else
          {[nil | body_list], [nil | signature_list]}
        end
      end)

    # reverse body/signature lists
    {body_list, signature_list} = {Enum.reverse(body_list), Enum.reverse(signature_list)}

    # parse body/signature lists
    {parsed_body_list, parsed_signature_list} =
      {body_list, signature_list}
      |> EpochtalkServer.BBCParser.parse_list_tuple()
      |> case do
        {:ok, parsed_tuple} ->
          parsed_tuple

        {:error, unparsed_tuple} ->
          Logger.error("#{__MODULE__}(tuple parse): #{inspect(unparsed_tuple)}")
          unparsed_tuple
      end

    zip_posts(posts, parsed_body_list, parsed_signature_list)
  end

  defp zip_posts(posts, parsed_body_list, parsed_signature_list) do
    # zip posts with body/signature lists
    zipped_posts =
      Enum.zip_with(
        [posts, parsed_body_list, parsed_signature_list],
        fn [post, parsed_body, parsed_signature] ->
          parsed_body =
            case parsed_body do
              {:ok, parsed_body} ->
                Logger.debug("#{__MODULE__}(body): post_id #{inspect(post.id)}")
                parsed_body

              {:timeout, unparsed_body} ->
                Logger.error("#{__MODULE__}(body timeout): post_id #{inspect(post.id)}")
                unparsed_body
            end

          parsed_signature =
            case parsed_signature do
              {:ok, parsed_signature} ->
                Logger.debug("#{__MODULE__}(signature): user_id #{inspect(post.user.id)}")
                parsed_signature

              {:timeout, unparsed_signature} ->
                Logger.error("#{__MODULE__}(signature timeout): user_id #{inspect(post.user.id)}")
                unparsed_signature
            end

          user = post.user |> Map.put(:signature, parsed_signature)

          post =
            if parsed_body do
              # post was parsed, store it in cache
              EpochtalkServer.Cache.ParsedPosts.put(post.id, %{
                body_html: parsed_body,
                updated_at: post.updated_at
              })

              post
              |> Map.put(:body_html, parsed_body)
              |> Map.put(:user, user)
            else
              # post was not parsed, get value from cache
              post =
                case EpochtalkServer.Cache.ParsedPosts.get(post.id) do
                  {:ok, cached_post} ->
                    post
                    |> Map.put(:body_html, cached_post.body_html)
                    |> Map.put(:user, user)

                  {:error, _} ->
                    nil
                end

              post
            end

          post
        end
      )

    EpochtalkServer.Cache.ParsedPosts.lookup_and_purge()
    zipped_posts
  end
end
