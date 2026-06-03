defmodule Agentic.Core.Cmd do
  defstruct [:type, :data]

  @type cmd_type ::
          :call_llm
          | :request_user_input
          | :request_approval
          | :send_response
          | :send_response_delta
          | :finish_session

  # 模型调用
  def call_llm(data \\ %{}), do: %__MODULE__{type: :call_llm, data: data}

  # 人机协同
  def request_user_input(data), do: %__MODULE__{type: :request_user_input, data: data}
  def request_approval(data), do: %__MODULE__{type: :request_approval, data: data}

  # 回复
  def send_response(data), do: %__MODULE__{type: :send_response, data: data}
  def send_response_delta(data), do: %__MODULE__{type: :send_response_delta, data: data}

  # 会话
  def finish_session(data \\ %{}), do: %__MODULE__{type: :finish_session, data: data}
end
