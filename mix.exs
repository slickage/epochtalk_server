defmodule EpochtalkServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :epochtalk_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {EpochtalkServer.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.1.2"},
      {:configparser_ex, "~> 4.0"},
      {:corsica, "~> 2.1.3"},
      {:credo, "~> 1.7.9", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:dotenv_parser, "~> 2.0"},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.12"},
      {:ex2ms, "~> 1.0"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:ex_doc, "~> 0.37.2"},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:ex_utils, "~> 0.1.7"},
      {:finch, "~> 0.13"},
      {:gen_smtp, "~> 1.2"},
      {:guardian, "~> 2.2"},
      {:guardian_phoenix, "~> 2.0"},
      {:guardian_db, "~> 3.0"},
      {:guardian_redis, "~> 0.2"},
      {:hackney, "~> 1.9"},
      {:hammer, "~> 6.2"},
      {:hammer_backend_redis, "~> 6.1"},
      {:html_entities, "~> 0.5.2", only: [:dev, :test]},
      {:html_sanitize_ex, "~> 1.4"},
      {:iteraptor, git: "https://github.com/epochtalk/elixir-iteraptor.git", tag: "1.13.1"},
      {:jason, "~> 1.4.0"},
      {:mimic, "~> 1.11.0", only: :test},
      {:myxql, "~> 0.7.1"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.2"},
      {:plug_cowboy, "~> 2.5"},
      {:poolboy, "~> 1.5.1"},
      {:porcelain, "~> 2.0"},
      {:poison, "~> 6.0"},
      {:postgrex, "~> 0.20.0"},
      {:redix, "~> 1.5.2"},
      {:remote_ip, "~> 1.2.0"},
      {:sweet_xml, "~> 0.7"},
      {:swoosh, "~> 1.8"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "seed.default"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "db.migrate": ["ecto.migrate", "ecto.dump"],
      "db.rollback": ["ecto.rollback", "ecto.dump"],
      # required seeds
      "seed.required": ["seed.prp", "seed.permissions", "seed.roles", "seed.rp"],
      "seed.prp": ["run priv/repo/process_roles_permissions.exs"],
      "seed.permissions": ["run priv/repo/seed_permissions.exs"],
      "seed.roles": ["run priv/repo/seed_roles.exs"],
      "seed.rp": ["run priv/repo/seed_roles_permissions.exs"],
      # forum seeds
      "seed.default": ["seed.required", "seed.forum"],
      "seed.forum": ["run priv/repo/seed_forum.exs"],
      "seed.user": ["run priv/repo/seed_user.exs"],
      # test seeds
      "seed.test": [
        "seed.required",
        "seed.test_users"
      ],
      "seed.test_users": ["run test/seed/users.exs"],
      test: [
        "ecto.drop",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "seed.test",
        "test"
      ]
    ]
  end
end
