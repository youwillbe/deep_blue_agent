defmodule Agentic.Provider.CtYun do
  use ReqLLM.Provider,
    id: :ctyun,
    default_base_url: "https://wishub-x6.ctyun.cn/v1"

  use ReqLLM.Provider.Defaults

  @provider_schema []
end
