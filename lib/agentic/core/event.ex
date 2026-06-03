defmodule Agentic.Core.Event do
  @moduledoc """
  Core.Loop 部分产出的所有 Event

  层级: Session → Turn → Step → (LLM Call | Tool Call)
  """
  defstruct [:type, :data]

  @type event_type ::
          :agent_error

          # 会话
          | :session_started
          | :session_ended

          # 用户消息
          | :user_message_received

          # 轮次
          | :agent_turn_started
          | :agent_turn_ended

          # 步骤
          | :agent_step_started
          | :agent_step_progress
          | :agent_step_completed
          | :agent_step_failed

          # 模型调用
          | :llm_call_requested
          | :llm_call_chunk
          | :llm_call_completed
          | :llm_call_failed

          # 工具调用
          | :tool_call_requested
          | :tool_call_result_received
          | :tool_call_failed

          # 回复
          | :agent_response_generated
          | :agent_response_delta

          # 上下文
          | :context_updated
          | :context_cleared
          | :context_compressed

          # 记忆
          | :memory_retrieved
          | :memory_stored
          | :memory_deleted
          | :memory_updated

          # 人机协同
          | :agent_waiting_for_user_input
          | :user_input_provided
          | :approval_requested
          | :approval_granted
          | :approval_denied

  ##################################################
  ### region 会话

  def session_started(session_id) do
    %__MODULE__{type: :session_started, data: %{session_id: session_id}}
  end

  def session_ended(session_id) do
    %__MODULE__{type: :session_ended, data: %{session_id: session_id}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 用户消息

  def user_message_received(content) do
    %__MODULE__{type: :user_message_received, data: %{content: content}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 轮次

  def agent_turn_started(turn_id) do
    %__MODULE__{type: :agent_turn_started, data: %{turn_id: turn_id}}
  end

  def agent_turn_ended(turn_id) do
    %__MODULE__{type: :agent_turn_ended, data: %{turn_id: turn_id}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 步骤

  def agent_step_started(step_id, step_type, turn_id) do
    %__MODULE__{
      type: :agent_step_started,
      data: %{turn_id: turn_id, step_id: step_id, step_type: step_type}
    }
  end

  def agent_step_progress(step_id, turn_id, data) do
    %__MODULE__{
      type: :agent_step_progress,
      data: Map.merge(data, %{turn_id: turn_id, step_id: step_id})
    }
  end

  def agent_step_completed(step_id, turn_id) do
    %__MODULE__{type: :agent_step_completed, data: %{turn_id: turn_id, step_id: step_id}}
  end

  def agent_step_failed(step_id, turn_id, reason) do
    %__MODULE__{type: :agent_step_failed, data: %{turn_id: turn_id, step_id: step_id, reason: reason}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 模型调用

  def llm_call_requested(step_id, turn_id, model) do
    %__MODULE__{
      type: :llm_call_requested,
      data: %{turn_id: turn_id, step_id: step_id, model: model}
    }
  end

  def llm_call_chunk(step_id, turn_id, content) do
    %__MODULE__{
      type: :llm_call_chunk,
      data: %{turn_id: turn_id, step_id: step_id, content: content}
    }
  end

  def llm_call_completed(step_id, turn_id, usage) do
    %__MODULE__{
      type: :llm_call_completed,
      data: %{turn_id: turn_id, step_id: step_id, usage: usage}
    }
  end

  def llm_call_failed(step_id, turn_id, reason) do
    %__MODULE__{
      type: :llm_call_failed,
      data: %{turn_id: turn_id, step_id: step_id, reason: reason}
    }
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 工具调用

  def tool_call_requested(step_id, turn_id, tool_name, args) do
    %__MODULE__{
      type: :tool_call_requested,
      data: %{turn_id: turn_id, step_id: step_id, tool_name: tool_name, args: args}
    }
  end

  def tool_call_result_received(step_id, turn_id, tool_name, result) do
    %__MODULE__{
      type: :tool_call_result_received,
      data: %{turn_id: turn_id, step_id: step_id, tool_name: tool_name, result: result}
    }
  end

  def tool_call_failed(step_id, turn_id, tool_name, reason) do
    %__MODULE__{
      type: :tool_call_failed,
      data: %{turn_id: turn_id, step_id: step_id, tool_name: tool_name, reason: reason}
    }
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 回复

  def agent_response_generated(turn_id, content) do
    %__MODULE__{type: :agent_response_generated, data: %{turn_id: turn_id, content: content}}
  end

  def agent_response_delta(turn_id, content) do
    %__MODULE__{type: :agent_response_delta, data: %{turn_id: turn_id, content: content}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 上下文

  def context_updated(session_id, summary) do
    %__MODULE__{type: :context_updated, data: %{session_id: session_id, summary: summary}}
  end

  def context_cleared(session_id) do
    %__MODULE__{type: :context_cleared, data: %{session_id: session_id}}
  end

  def context_compressed(session_id, ratio) do
    %__MODULE__{type: :context_compressed, data: %{session_id: session_id, ratio: ratio}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 记忆

  def memory_retrieved(session_id, memories) do
    %__MODULE__{type: :memory_retrieved, data: %{session_id: session_id, memories: memories}}
  end

  def memory_stored(session_id, key, value) do
    %__MODULE__{type: :memory_stored, data: %{session_id: session_id, key: key, value: value}}
  end

  def memory_deleted(session_id, key) do
    %__MODULE__{type: :memory_deleted, data: %{session_id: session_id, key: key}}
  end

  def memory_updated(session_id, key, value) do
    %__MODULE__{type: :memory_updated, data: %{session_id: session_id, key: key, value: value}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 人机协同

  def agent_waiting_for_user_input(turn_id) do
    %__MODULE__{type: :agent_waiting_for_user_input, data: %{turn_id: turn_id}}
  end

  def user_input_provided(turn_id, content) do
    %__MODULE__{type: :user_input_provided, data: %{turn_id: turn_id, content: content}}
  end

  def approval_requested(turn_id, action) do
    %__MODULE__{type: :approval_requested, data: %{turn_id: turn_id, action: action}}
  end

  def approval_granted(turn_id, action) do
    %__MODULE__{type: :approval_granted, data: %{turn_id: turn_id, action: action}}
  end

  def approval_denied(turn_id, action) do
    %__MODULE__{type: :approval_denied, data: %{turn_id: turn_id, action: action}}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region 错误

  def agent_error(turn_id, reason) do
    %__MODULE__{type: :agent_error, data: %{turn_id: turn_id, reason: reason}}
  end

  ### endregion
  ##################################################
end
