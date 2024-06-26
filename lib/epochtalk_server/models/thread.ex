defmodule EpochtalkServer.Models.Thread do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias EpochtalkServer.Repo
  alias EpochtalkServerWeb.Helpers.ACL
  alias EpochtalkServer.Models.User
  alias EpochtalkServer.Models.Thread
  alias EpochtalkServer.Models.MetadataThread
  alias EpochtalkServer.Models.Board
  alias EpochtalkServer.Models.Poll
  alias EpochtalkServer.Models.Post

  @moduledoc """
  `Thread` model, for performing actions relating to forum threads
  """
  @type t :: %__MODULE__{
          id: non_neg_integer | nil,
          board_id: non_neg_integer | nil,
          locked: boolean | nil,
          sticky: boolean | nil,
          slug: String.t() | nil,
          moderated: boolean | nil,
          post_count: non_neg_integer | nil,
          created_at: NaiveDateTime.t() | nil,
          imported_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }
  @derive {Jason.Encoder,
           only: [
             :id,
             :board_id,
             :locked,
             :sticky,
             :slug,
             :moderated,
             :post_count,
             :created_at,
             :updated_at,
             :imported_at
           ]}
  schema "threads" do
    belongs_to :board, Board
    field :locked, :boolean
    field :sticky, :boolean
    field :slug, :string
    field :moderated, :boolean
    field :post_count, :integer
    field :created_at, :naive_datetime
    field :imported_at, :naive_datetime
    field :updated_at, :naive_datetime
    has_many :posts, Post
    # field :smf_topic, :map, virtual: true
  end

  ## === Changesets Functions ===

  @doc """
  Create generic changeset for `Thread` model
  """
  @spec changeset(thread :: t(), attrs :: map() | nil) :: Ecto.Changeset.t()
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :id,
      :board_id,
      :locked,
      :sticky,
      :slug,
      :moderated,
      :post_count,
      :created_at,
      :imported_at,
      :updated_at
    ])
    |> unique_constraint(:id, name: :threads_pkey)
    |> unique_constraint(:slug, name: :threads_slug_index)
    |> foreign_key_constraint(:board_id, name: :threads_board_id_fkey)
  end

  @doc """
  Create changeset for creation of `Thread` model
  """
  @spec create_changeset(thread :: t(), attrs :: map() | nil) :: Ecto.Changeset.t()
  def create_changeset(thread, attrs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    # set default values and timestamps
    thread =
      thread
      |> Map.put(:locked, false)
      |> Map.put(:sticky, false)
      |> Map.put(:moderated, false)
      |> Map.put(:created_at, now)

    thread
    |> cast(attrs, [
      :board_id,
      :locked,
      :sticky,
      :slug,
      :moderated,
      :post_count,
      :created_at
    ])
    |> validate_required([:board_id, :locked, :sticky, :slug, :moderated, :created_at])
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-zA-Z0-9-_](-?[a-zA-Z0-9-_])*$/)
    |> unique_constraint(:id, name: :threads_pkey)
    |> unique_constraint(:slug, name: :threads_slug_index)
    |> foreign_key_constraint(:board_id, name: :threads_board_id_fkey)
  end

  ## === Database Functions ===

  @doc """
  Creates a new `Thread` in the database
  """
  @spec create(thread_attrs :: map(), user :: map()) ::
          {:ok, thread :: t()} | {:error, Ecto.Changeset.t()}
  def create(thread_attrs, user) do
    thread_cs = create_changeset(%Thread{}, thread_attrs)

    case Repo.transaction(fn ->
           db_thread =
             case Repo.insert(thread_cs) do
               {:ok, db_thread} -> db_thread
               # rollback and bubble up changeset error
               {:error, cs} -> Repo.rollback(cs)
             end

           # create thread metadata
           MetadataThread.insert(%MetadataThread{thread_id: db_thread.id, views: 0})
           # create poll, if necessary
           db_poll = handle_create_poll(db_thread.id, thread_attrs["poll"], user)
           # create post
           db_post = handle_create_post(db_thread.id, thread_attrs, user)
           # return post (preloaded thread) and poll data
           %{post: db_post, poll: db_poll}
         end) do
      # transaction success return post with preloaded thread
      {:ok, thread_data} ->
        {:ok, thread_data}

      # handle slug conflict, add hash to slug, try to insert again
      {:error,
       %Ecto.Changeset{
         errors: [
           slug:
             {"has already been taken",
              [constraint: :unique, constraint_name: "threads_slug_index"]}
         ]
       } = _cs} ->
        hash =
          :crypto.strong_rand_bytes(3)
          |> Base.url_encode64()
          |> binary_part(0, 3)
          |> String.downcase()

        hashed_slug = "#{Map.get(thread_attrs, "slug")}-#{hash}"
        thread_attrs = thread_attrs |> Map.put("slug", hashed_slug)
        create(thread_attrs, user)

      # some other error
      {:error, cs} ->
        {:error, cs}
    end
  end

  @doc """
  Returns boolean indicating if `Thread` is locked or nil if it does not exist
  """
  @spec locked?(id :: non_neg_integer) :: boolean | nil
  def locked?(id) when is_integer(id) do
    query =
      from t in Thread,
        where: t.id == ^id,
        select: t.locked

    Repo.one(query)
  end

  @doc """
  Increments the `post_count` field given a `Thread` id
  """
  @spec increment_post_count(id :: non_neg_integer) :: {non_neg_integer(), nil}
  def increment_post_count(id) do
    query = from t in Thread, where: t.id == ^id
    Repo.update_all(query, inc: [post_count: 1])
  end

  @doc """
  Sets the `created_at` and `updated_at` of a new `Thread` by querying it's posts.
  """
  @spec set_timestamps(id :: non_neg_integer) :: {non_neg_integer(), nil}
  def set_timestamps(id) do
    # get created_at of first post in thread
    created_at_query =
      from p in Post,
        where: p.thread_id == ^id,
        order_by: [p.created_at],
        limit: 1,
        select: p.created_at

    created_at = Repo.one(created_at_query)

    # get created_at of last post in thread
    updated_at_query =
      from p in Post,
        where: p.thread_id == ^id,
        order_by: [desc: p.created_at],
        limit: 1,
        select: p.created_at

    updated_at = Repo.one(updated_at_query)

    # set created_at and updated_at of thread
    from(t in Thread, where: t.id == ^id)
    |> Repo.update_all(
      set: [
        created_at: created_at,
        updated_at: updated_at
      ]
    )
  end

  @doc """
  Returns recent threads accounting for user priority and user's ignored boards
  """
  # TODO(akinsey): complete implementation for main view
  @spec recent(user :: User.t(), user_priority :: non_neg_integer, opts :: list() | nil) :: [t()]
  def recent(_user, _user_priority, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    query =
      from Thread,
        order_by: [desc: :updated_at],
        limit: ^limit

    Repo.all(query)
  end

  @doc """
  Returns paged threads by `Board` given a `board_id`
  """
  @spec page_by_board_id(
          board_id :: non_neg_integer,
          page :: non_neg_integer | nil,
          opts :: list() | nil
        ) :: %{normal: [map()] | [], sticky: [map()] | []}
  def page_by_board_id(board_id, page \\ 1, opts \\ []) do
    user = Keyword.get(opts, :user)
    user_id = if is_nil(user), do: nil, else: Map.get(user, :id)
    per_page = Keyword.get(opts, :per_page, 25)
    field = Keyword.get(opts, :field, "updated_at")
    reversed = Keyword.get(opts, :desc, false)
    offset = page * per_page - per_page

    opts =
      opts
      |> Keyword.put(:user_id, user_id)
      |> Keyword.put(:per_page, per_page)
      |> Keyword.put(:field, field)
      |> Keyword.put(:reversed, reversed)
      # duplicate reversed for outer query
      |> Keyword.put(:sort_order, reversed)
      |> Keyword.put(:offset, offset)

    %{
      sticky: sticky_by_board_id(board_id, page, opts),
      normal: normal_by_board_id(board_id, page, opts)
    }
  end

  @doc """
  Returns a specific `Thread` given a valid `id` or `slug`
  """
  @spec find(id_or_slug :: non_neg_integer | String.t()) :: map() | nil
  def find(id) when is_integer(id) do
    initial_query =
      from t in Thread,
        where: t.id == ^id,
        select: %{
          id: t.id,
          board_id: t.board_id,
          slug: t.slug,
          locked: t.locked,
          sticky: t.sticky,
          moderated: t.moderated,
          post_count: t.post_count,
          created_at: t.created_at,
          updated_at: t.updated_at
        }

    find_shared(initial_query)
  end

  def find(slug) when is_binary(slug) do
    initial_query =
      from t in Thread,
        where: t.slug == ^slug,
        select: %{
          id: t.id,
          board_id: t.board_id,
          slug: t.slug,
          locked: t.locked,
          sticky: t.sticky,
          moderated: t.moderated,
          post_count: t.post_count,
          created_at: t.created_at,
          updated_at: t.updated_at
        }

    find_shared(initial_query)
  end

  @doc """
  Convert `Thread` `slug` to `id`
  """
  @spec slug_to_id(slug :: String.t()) ::
          {:ok, id :: non_neg_integer} | {:error, :thread_does_not_exist}
  def slug_to_id(slug) when is_binary(slug) do
    query =
      from t in Thread,
        where: t.slug == ^slug,
        select: t.id

    id = Repo.one(query)

    if id,
      do: {:ok, id},
      else: {:error, :thread_does_not_exist}
  end

  @doc """
  Check if specific `Thread` is self moderated by a specific `User`
  """
  @spec self_moderated_by_user?(id :: non_neg_integer, user_id :: non_neg_integer) ::
          boolean
  def self_moderated_by_user?(id, user_id) do
    query_first_thread_post =
      from p in Post,
        left_join: t in Thread,
        on: t.id == p.thread_id,
        order_by: [p.created_at],
        limit: 1,
        where: p.thread_id == ^id,
        select: %{moderated: t.moderated, user_id: p.user_id}

    first_post = Repo.one(query_first_thread_post)

    first_post != nil and first_post.user_id == user_id and first_post.moderated
  end

  @doc """
  Check if specific `Thread`, using a `post_id`, is self moderated by a specific `User`
  """
  @spec self_moderated_by_user_with_post_id?(
          post_id :: non_neg_integer,
          user_id :: non_neg_integer
        ) ::
          boolean
  def self_moderated_by_user_with_post_id?(post_id, user_id) do
    query_first_thread_post =
      from p in Post,
        left_join: t in Thread,
        on: t.id == p.thread_id,
        order_by: [p.created_at],
        limit: 1,
        where: p.id == ^post_id,
        select: %{moderated: t.moderated, user_id: p.user_id}

    first_post = Repo.one(query_first_thread_post)

    first_post != nil and first_post.user_id == user_id and first_post.moderated
  end

  @doc """
  Used to obtain breadcrumb data for a specific `Thread` given it's `slug`
  """
  @spec breadcrumb(slug :: String.t()) ::
          {:ok, thread :: t()} | {:error, :thread_does_not_exist}
  def breadcrumb(slug) when is_binary(slug) do
    post_query =
      from p in Post,
        order_by: p.created_at,
        limit: 1

    thread_query =
      from t in Thread,
        where: t.slug == ^slug,
        preload: [:board, posts: ^post_query]

    thread = Repo.one(thread_query)

    if thread,
      do: {:ok, thread},
      else: {:error, :thread_does_not_exist}
  end

  @doc """
  Used to get first `Post` data given a `Thread` id
  """
  @spec get_first_post_data_by_id(id :: non_neg_integer) ::
          post_data :: map() | nil
  def get_first_post_data_by_id(id) when is_integer(id) do
    query_first_thread_post_data =
      from p in Post,
        left_join: t in Thread,
        on: t.id == p.thread_id,
        left_join: u in User,
        on: u.id == p.user_id,
        where: p.thread_id == ^id,
        order_by: [p.created_at],
        limit: 1,
        select: %{
          id: p.id,
          title: p.content["title"],
          body: p.content["body"],
          thread_id: p.thread_id,
          thread_slug: t.slug,
          username: u.username,
          user_id: u.id,
          user: u
        }

    first_post = Repo.one(query_first_thread_post_data)
    Map.put(first_post, :user, Repo.preload(first_post.user, :roles))
  end

  @doc """
  Used to get first `Post` data given a `Thread` slug
  """
  @spec get_first_post_data_by_id(slug :: String.t()) ::
          post_data :: map() | nil
  def get_first_post_data_by_slug(slug) when is_binary(slug) do
    query_first_thread_post_data =
      from p in Post,
        left_join: t in Thread,
        on: t.id == p.thread_id,
        left_join: u in User,
        on: u.id == p.user_id,
        where: t.slug == ^slug,
        order_by: [p.created_at],
        limit: 1,
        select: %{
          id: p.id,
          title: p.content["title"],
          body: p.content["body"],
          thread_id: p.thread_id,
          thread_slug: t.slug,
          username: u.username,
          user_id: u.id,
          user: u
        }

    first_post = Repo.one(query_first_thread_post_data)
    Map.put(first_post, :user, Repo.preload(first_post.user, :roles))
  end

  ## === Private Helper Functions ===

  defp find_shared(initial_query) do
    query =
      from(t in subquery(initial_query))
      |> join(
        :left_lateral,
        [t],
        p in fragment(
          """
            SELECT
              p1.user_id, p1.content ->> \'title\' as title, u.username, u.deleted as user_deleted
              FROM posts p1
              LEFT JOIN users u on p1.user_id = u.id
              WHERE p1.thread_id = ?
              ORDER BY p1.created_at
              LIMIT 1
          """,
          t.id
        ),
        on: true
      )
      |> select([t, p], %{
        id: t.id,
        board_id: t.board_id,
        slug: t.slug,
        locked: t.locked,
        sticky: t.sticky,
        moderated: t.moderated,
        created_at: t.created_at,
        updated_at: t.updated_at,
        post_count: t.post_count,
        user_id: p.user_id,
        title: p.title,
        username: p.username,
        user_deleted: p.user_deleted
      })

    Repo.one(query)
  end

  defp sticky_by_board_id(board_id, page, opts) when page == 1,
    do: generate_thread_query(board_id, true, opts) |> Repo.all()

  defp sticky_by_board_id(_board_id, page, _opts) when page != 1, do: []

  defp normal_by_board_id(board_id, _page, opts) do
    normal_count_query = from b in Board, where: b.id == ^board_id, select: b.thread_count

    sticky_count_query =
      from t in Thread, where: t.board_id == ^board_id and t.sticky == true, select: count(t.id)

    normal_thread_count = normal_count_query |> Repo.one()
    sticky_thread_count = sticky_count_query |> Repo.one()

    thread_count = if normal_thread_count, do: normal_thread_count - sticky_thread_count

    # determine wheter to start from front or back
    opts =
      if not is_nil(thread_count) and opts[:offset] > floor(thread_count / 2) do
        # invert reverse
        reversed = !opts[:reversed]
        opts = Keyword.put(opts, :reversed, reversed)

        # calculate new per_page
        per_page =
          if thread_count <= opts[:offset] + opts[:per_page],
            do: abs(thread_count - opts[:offset]),
            else: opts[:per_page]

        opts = Keyword.put(opts, :per_page, per_page)

        # calculate new offset after modifying per_page
        offset =
          if thread_count <= opts[:offset] + opts[:per_page],
            do: 0,
            else: thread_count - opts[:offset] - opts[:per_page]

        Keyword.put(opts, :offset, offset)
      else
        opts
      end

    generate_thread_query(board_id, false, opts) |> Repo.all()
  end

  defp generate_thread_query(board_id, sticky, opts) do
    # get base threads with metadata to join onto
    inner_query =
      Thread
      |> join(:left, [t2], mt in MetadataThread, on: t2.id == mt.thread_id)
      |> where(
        [t2, mt],
        t2.board_id == ^board_id and t2.sticky == ^sticky and not is_nil(t2.updated_at)
      )
      |> select([t2, mt], %{
        id: t2.id,
        updated_at: t2.updated_at,
        views: mt.views,
        created_at: t2.created_at,
        post_count: t2.post_count
      })

    # if not sticky attach limit and offset to inner query
    inner_query =
      if sticky,
        do: inner_query,
        else: inner_query |> limit(^opts[:per_page]) |> offset(^opts[:offset])

    # handle sort field and direction
    field = String.to_atom(opts[:field])
    direction = if opts[:reversed], do: :desc, else: :asc

    # sort by field in joined metadata thread table if sort field is 'view'
    inner_query =
      if field == :views,
        do: inner_query |> order_by([t, mt], [{^direction, mt.views}]),
        else: inner_query |> order_by([t], [{^direction, field(t, ^field)}])

    # outer query
    sort_order = if opts[:sort_order], do: :desc, else: :asc

    from(tlist in subquery(inner_query))
    # join thread info
    |> join(
      :left_lateral,
      [tlist],
      t in fragment(
        """
          SELECT t1.locked, t1.sticky, t1.slug, t1.moderated,
            t1.post_count, t1.created_at, t1.updated_at, mt.views,
            (SELECT EXISTS ( SELECT 1 FROM polls WHERE thread_id = ? )) as poll,
            (SELECT time FROM users.thread_views WHERE thread_id = ? AND user_id = ?)
          FROM threads t1
          LEFT JOIN metadata.threads mt ON ? = mt.thread_id
          WHERE t1.id = ?
        """,
        tlist.id,
        tlist.id,
        ^opts[:user_id],
        tlist.id,
        tlist.id
      ),
      on: true
    )
    # join thread title and author info
    |> join(
      :left_lateral,
      [tlist],
      p in fragment(
        """
          SELECT p1.content ->> \'title\' as title, p1.user_id,
            u.username, u.deleted as user_deleted
          FROM posts p1
          LEFT JOIN users u ON p1.user_id = u.id
          WHERE p1.thread_id = ?
          ORDER BY p1.created_at
          LIMIT 1
        """,
        tlist.id
      ),
      on: true
    )
    # join post id and post position
    |> join(
      :left_lateral,
      [tlist, t],
      tv in fragment(
        """
          SELECT id, position
          FROM posts
          WHERE thread_id = ? AND created_at >= ?
          ORDER BY created_at
          LIMIT 1
        """,
        tlist.id,
        t.time
      ),
      on: true
    )
    # join last post info
    |> join(
      :left_lateral,
      [tlist],
      pl in fragment(
        """
          SELECT p.id AS last_post_id, p.position, p.created_at, p.deleted,
           u.id, u.username, u.deleted as user_deleted, up.avatar
         FROM posts p
         LEFT JOIN users u ON p.user_id = u.id
         LEFT JOIN users.profiles up ON p.user_id = up.user_id
         WHERE p.thread_id = ?
         ORDER BY p.created_at DESC
         LIMIT 1
        """,
        tlist.id
      ),
      on: true
    )
    |> select([tlist, t, p, tv, pl], %{
      id: tlist.id,
      slug: t.slug,
      locked: t.locked,
      sticky: t.sticky,
      moderated: t.moderated,
      poll: t.poll,
      created_at: t.created_at,
      updated_at: t.updated_at,
      post_count: t.post_count,
      last_viewed: t.time,
      view_count: tlist.views,
      title: p.title,
      user_id: p.user_id,
      username: p.username,
      user_deleted: p.user_deleted,
      post_id: tv.id,
      post_position: tv.position,
      last_post_id: pl.last_post_id,
      last_post_position: pl.position,
      last_post_created_at: pl.created_at,
      last_post_deleted: pl.deleted,
      last_post_user_id: pl.id,
      last_post_username: pl.username,
      last_post_user_deleted: pl.user_deleted,
      last_post_avatar: pl.avatar
    })
    |> order_by([tlist], [{^sort_order, field(tlist, ^field)}])
  end

  defp handle_create_poll(_thread_id, nil, _user), do: nil

  defp handle_create_poll(thread_id, poll_attrs, user) when is_map(poll_attrs) do
    # check if user has permissions to create poll
    ACL.allow!(user, "threads.createPoll")

    # append thread_id
    poll_attrs = Map.put(poll_attrs, "thread_id", thread_id)

    # create poll, with modified poll data (thread_id added)
    case Poll.create(poll_attrs) do
      # create success
      {:ok, poll} -> poll
      # error creating poll
      {:error, cs} -> Repo.rollback(cs)
    end
  end

  defp handle_create_post(thread_id, thread_attrs, user) do
    post_attrs = %{
      thread_id: thread_id,
      user_id: user.id,
      content: %{
        title: thread_attrs["title"],
        body: thread_attrs["body"],
        body_html: thread_attrs["body_html"]
      }
    }

    case Post.create(post_attrs) do
      {:ok, post} -> post
      {:error, cs} -> Repo.rollback(cs)
    end
  end
end
