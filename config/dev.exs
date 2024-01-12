import Config

# Configure your database
config :epochtalk_server, EpochtalkServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "epochtalk_server_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :epochtalk_server, EpochtalkServer.SmfRepo,
  username: System.get_env("SMF_REPO_USERNAME"),
  password: System.get_env("SMF_REPO_PASSWORD"),
  hostname: System.get_env("SMF_REPO_HOSTNAME"),
  database: System.get_env("SMF_REPO_DATABASE"),
  port: System.get_env("SMF_REPO_PORT") |> String.to_integer(),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 5

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with esbuild to bundle .js and .css sources.
config :epochtalk_server, EpochtalkServerWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: false,
  secret_key_base: "9ORa6oGSN+xlXNedSn0gIKVc/6//naQqSiZsRJ8vNbcvHpPOTPMLgcn134WIH3Pd",
  watchers: []

# Configure Local Mailer by default for dev mode (this can be overridden in dev.secret.exs)
config :epochtalk_server, EpochtalkServer.Mailer, adapter: Swoosh.Adapters.Local

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Note that this task requires Erlang/OTP 20 or later.
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

if File.exists?("config/dev.secret.exs") do
  import_config "dev.secret.exs"
end
