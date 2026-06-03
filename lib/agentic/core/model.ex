defmodule Agentic.Core.Model do
  defstruct [
    :provider,
    :base_url,
    :chat_path,
    :api_key,
    :model,
    max_tokens: 4096
  ]
end
