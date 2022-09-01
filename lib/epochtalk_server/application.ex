defmodule EpochtalkServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start Guardian Redis Redix connection
      GuardianRedis.Redix,
      # Start the Ecto repository
      EpochtalkServer.Repo,
      # Start the Telemetry supervisor
      EpochtalkServerWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: EpochtalkServer.PubSub},
      # Start the Endpoint (http/https)
      EpochtalkServerWeb.Endpoint
      # Start a worker by calling: EpochtalkServer.Worker.start_link(arg)
      # {EpochtalkServer.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EpochtalkServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EpochtalkServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end