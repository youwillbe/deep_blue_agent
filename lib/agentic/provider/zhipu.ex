defmodule Agentic.Provider.ZhiPu do
  use ReqLLM.Provider,
    id: :zhipu,
    default_base_url: "https://open.bigmodel.cn/api/coding/paas/v4",
    default_env_key: "ZHIPU_API_KEY"

  use ReqLLM.Provider.Defaults

  @provider_schema [
    thinking: [
      type: :map,
      doc:
        ~s(Control thinking/reasoning mode. Set to %{type: "disabled"} to disable or %{type: "enabled"} to enable.)
    ]
  ]

  # Delegate all callbacks to ReqLLM.Providers.ZaiCoder
  @impl ReqLLM.Provider
  def prepare_request(operation, model_spec, input, opts) do
    ReqLLM.Provider.Defaults.prepare_request(__MODULE__, operation, model_spec, input, opts)
  end

  @impl ReqLLM.Provider
  def attach(request, model_input, user_opts) do
    context = Map.get(request.options, :context)

    default_timeout =
      if context && Map.get(context, :__thinking_mode__, false) do
        Application.get_env(:req_llm, :thinking_timeout, 300_000)
      else
        Application.get_env(:req_llm, :receive_timeout, 120_000)
      end

    timeout = Keyword.get(user_opts, :receive_timeout, default_timeout)

    updated_request =
      request
      |> Map.update!(:options, fn opts ->
        opts
        |> Map.put(:receive_timeout, timeout)
        |> Map.put(:pool_timeout, timeout)
      end)

    ReqLLM.Provider.Defaults.default_attach(__MODULE__, updated_request, model_input, user_opts)
  end

  defdelegate encode_body(request), to: ReqLLM.Providers.ZaiCoder

  defdelegate decode_response(request_response), to: ReqLLM.Providers.ZaiCoder

  defdelegate translate_options(operation, model, opts), to: ReqLLM.Providers.ZaiCoder

  defdelegate extract_usage(data, model), to: ReqLLM.Providers.ZaiCoder

  @impl ReqLLM.Provider
  def attach_stream(model, context, opts, finch_name) do
    processed_opts =
      ReqLLM.Provider.Options.process_stream!(
        __MODULE__,
        opts[:operation] || :chat,
        model,
        context,
        opts
      )

    ReqLLM.Provider.Defaults.default_attach_stream(
      __MODULE__,
      model,
      context,
      processed_opts,
      finch_name
    )
  end

  defdelegate decode_stream_event(event, model), to: ReqLLM.Providers.ZaiCoder
end
