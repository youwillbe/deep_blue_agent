# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :deep_blue, DeepBlue.Jido,
  max_tasks: 1000,
  agent_pools: []

# 添加自定义 Provider
config :req_llm,
  custom_providers: [
    Agentic.Provider.CtYun,
    Agentic.Provider.ZhiPu
  ]

# 添加自定义模型
config :llm_db,
  custom: %{
    ctyun: [
      name: "电信",
      base_url: "https://wishub-x6.ctyun.cn/v1",
      env: ["CTYUN_API_KEY"],
      models: %{
        "deepseek-v4-flash" => %{
          provider_model_id: "f23c54bf38b64ee194b28783d61be788",
          capabilities: %{chat: true}
        },
        "glm-5.1" => %{
          provider_model_id: "5fea387da7f54ba38eab3d4a4fb4e9d8",
          capabilities: %{chat: true}
        }
      }
    ],
    zhipu: [
      name: "智谱",
      base_url: "https://open.bigmodel.cn/api/coding/paas/v4",
      env: ["ZHIPU_API_KEY"],
      models: %{
        "glm-5.1" => %{
          capabilities: %{chat: true}
        },
        "glm-5-turbo" => %{
          capabilities: %{chat: true}
        }
      }
    ]
  }

config :deep_blue,
  ecto_repos: [DeepBlue.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :deep_blue, DeepBlueWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DeepBlueWeb.ErrorHTML, json: DeepBlueWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DeepBlue.PubSub,
  live_view: [signing_salt: "tzLKEdYj"]


# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  deep_blue: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  deep_blue: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
