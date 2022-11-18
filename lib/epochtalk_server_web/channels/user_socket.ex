defmodule EpochtalkServerWeb.UserSocket do
  use Phoenix.Socket
  @moduledoc """
  Handles `User` socket connection and authentication.
  """

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels
  channel "user:*", EpochtalkServerWeb.UserChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(params, socket, connect_info), do: connect_maybe_auth(params, socket, connect_info)

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     Elixir.EpochtalkServerWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: maybe_socket_id(socket)

  @doc """
  Connects to socket and authenticates if token is provided, still connects anonymously if token is not provided.
  """
  @spec connect_maybe_auth(params :: map(), socket :: Phoenix.Socket.t(), connect_info :: map()) ::  {:ok, Phoenix.Socket.t()} | {:error, term()} | :error
  def connect_maybe_auth(%{"token" => token} = _params, socket, _connect_info) do
    case Guardian.Phoenix.Socket.authenticate(socket, EpochtalkServer.Auth.Guardian, token) do
      {:ok, authed_socket } -> {:ok, authed_socket |> assign(:user_id, authed_socket.assigns[:guardian_default_resource].id)}
      {:error, _reason} -> :error
    end
  end
  def connect_maybe_auth(_params, socket, _connect_info), do: {:ok, socket}

  @doc """
  Returns socket id `"user:<user_id>"` if authenticated and `nil` if not authenticated.
  """
  @spec maybe_socket_id(socket :: Phoenix.Socket.t()) :: String.t() | nil
  def maybe_socket_id(%{assigns: %{user_id: user_id}} = _socket), do: "user:#{user_id}"
  def maybe_socket_id(_socket), do: nil
end
