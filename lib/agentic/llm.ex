defmodule Agentic.LLM do
  def call(context) do
    # IO.inspect("calling LLM")
    # IO.inspect(context, label: "context", pretty: true, width: 0)
    {:ok, response} = ReqLLM.generate_text("zai_coding_plan:glm-4.7", context)
    response
  end

  def call_stream(context) do
    {:ok, stream_response} =
      ReqLLM.stream_text("zai_coding_plan:glm-4.7", context, receive_timeout: 60_000)

    stream_response
  end
end
