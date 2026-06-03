defmodule Agentic.Core.Msg do
  @typedoc "用户针对等待输入的响应"
  @type user_input :: {:user_input_provided, step_id :: String.t(), data :: map()}

  @typedoc "审批回复"
  @type approval_response ::
          {:approval_response, step_id :: String.t(), approved :: boolean(),
           comment :: String.t() | nil}

  ##################################################
  ### region user_message

  @type user_message :: {:user_message, content :: any()}

  @doc """
  用户发送的聊天消息
  """
  def user_message(content), do: {:user_message, content}

  ### endregion
  ##################################################

  ##################################################
  ### region LLM_chunk

  @type llm_chunk :: {:llm_chunk, step_id :: String.t(), delta :: String.t()}

  @doc """
  LLM 流式片段
  """
  def llm_chunk(step_id, delta), do: {:llm_chunk, step_id, delta}

  ### endregion
  ##################################################

  ##################################################
  ### region LLM_done

  @typedoc "LLM 生成完成"
  @type llm_done ::
          {:llm_done, step_id :: String.t(), full_response :: String.t(), usage :: map()}

  ### endregion
  ##################################################

  ##################################################
  ### region LLM_error

  @typedoc "LLM 调用失败"
  @type llm_error :: {:llm_error, step_id :: String.t(), reason :: String.t()}

  ### endregion
  ##################################################

  ##################################################
  ### region tool_result

  @type tool_result :: {:tool_result, tool_use_id :: String.t(), result :: term()}

  @doc """
  工具执行结果
  """
  def tool_result(tool_use_id, result), do: {:tool_result, tool_use_id, result}

  ### endregion
  ##################################################

  ##################################################
  ### region continue

  @typedoc "内部继续信号"
  @type continue :: :continue

  ### endregion
  ##################################################

  ##################################################
  ### region type

  @type t ::
          user_message
          | user_input
          | tool_result
          | llm_chunk
          | llm_done
          | llm_error
          | approval_response
          | continue

  ### endregion
  ##################################################
end
