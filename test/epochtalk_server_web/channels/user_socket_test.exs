defmodule Test.EpochtalkServerWeb.UserSocket do
  use Test.Support.ChannelCase
  alias EpochtalkServerWeb.UserSocket
  alias EpochtalkServer.Auth.Guardian

  describe "connect/3" do
    test "given invalid JWT, returns :error" do
      assert connect(UserSocket, %{token: "bad_token"}) == :error
    end

    test "given valid JWT without backing user, returns :error" do
      {:ok, token, _claims} = Guardian.encode_and_sign(%{user_id: :rand.uniform(9999)})
      assert connect(UserSocket, %{token: token}) == :error
    end

    @tag :authenticated
    test "given valid JWT with backing user, returns authenticated socket", %{
      user_id: user_id,
      token: token
    } do
      assert {:ok, %Phoenix.Socket{assigns: %{user_id: ^user_id}}} =
               connect(UserSocket, %{token: token})
    end

    test "with anonymous connection, returns unauthenticated socket" do
      assert {:ok, %Phoenix.Socket{}} = connect(UserSocket, %{})
    end
  end
end
