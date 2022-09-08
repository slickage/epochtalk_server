defmodule EpochtalkServer.Models.User do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias EpochtalkServer.Repo
  alias EpochtalkServer.Models.User
  alias EpochtalkServer.Models.Profile
  alias EpochtalkServer.Models.Preference

  schema "users" do
    field :email, :string
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :passhash, :string
    field :confirmation_token, :string
    field :reset_token, :string
    field :reset_expiration, :string

    field :created_at, :naive_datetime
    field :imported_at, :naive_datetime
    field :updated_at, :naive_datetime
    field :deleted, :boolean, default: false
    field :malicious_score, :integer

    field :smf_member, :map, virtual: true
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :email, :username, :created_at, :updated_at, :deleted, :malicious_score, :password])
    |> unique_constraint(:id, name: :users_pkey)
    |> validate_username()
    |> validate_email()
    |> validate_password()
  end

  def with_username_exists?(username), do: Repo.exists?(from u in User, where: u.username == ^username)
  def with_email_exists?(email), do: Repo.exists?(from u in User, where: u.email == ^email)
  def by_id(id) when is_integer(id), do: Repo.get_by(User, id: id)
  def by_username(username) when is_binary(username) do
    query = from u in User,
    left_join: p in Profile,
      on: u.id == p.user_id,
    left_join: pr in Preference,
      on: u.id == pr.user_id,
    select: %{
      id: u.id,
      username: u.username,
      email: u.email,
      passhash: u.passhash,
      confirmation_token: u.confirmation_token,
      reset_token: u.reset_token,
      reset_expiration: u.reset_expiration,
      deleted: u.deleted,
      malicious_score: u.malicious_score,
      created_at: u.created_at,
      updated_at: u.updated_at,
      imported_at: u.imported_at,
      avatar: p.avatar,
      position: p.position,
      signature: p.signature,
      raw_signature: p.raw_signature,
      fields: p.fields,
      post_count: p.post_count,
      last_active: p.last_active,
      posts_per_page: pr.posts_per_page,
      threads_per_page: pr.threads_per_page,
      collapsed_categories: pr.collapsed_categories,
      ignored_boards: pr.ignored_boards,
      ban_expiration: fragment("""
        CASE WHEN EXISTS (
          SELECT user_id
          FROM roles_users
          WHERE role_id = (SELECT id FROM roles WHERE lookup = \'banned\') and user_id = ?
        )
        THEN (
          SELECT expiration
          FROM users.bans
          WHERE user_id = ?
        )
        ELSE NULL END
      """, u.id, u.id)},
    where: u.username == ^username
    Repo.one(query)
  end
  def by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username)
    if User.valid_password?(user, password), do: user
  end
  def valid_password?(%User{passhash: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end
  defp validate_username(changeset) do
    changeset
    |> validate_required(:username)
    |> unique_constraint(:username)
  end
  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Repo)
    |> unique_constraint(:email)
  end
  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    # check that password matches password_confirmation
    #   checks that password and password_confirmation match
    #   but does not require password_confirmation to be supplied
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_length(:password, min: 8, max: 72)
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> hash_password()
  end
  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:passhash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
