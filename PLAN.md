# Deep Blue 多租户SaaS系统实施计划

## 第一阶段：租户和用户管理

系统分为三层：

- **运营后台**（/console）：内部运营人员使用，管理所有租户、全局配置
- **租户后台**（/admin）：租户管理员使用，管理自己的用户、agent、知识库等
- **租户前台**（/）：租户用户使用，chat、agent交互

两套独立认证体系：OperatorUser 和 User 是两张独立的表，各自带角色字段。Tenant 是独立 context。

### ✅ Step 1: 运营后台

```bash
mix phx.gen.auth Operator OperatorUser operator_users
```

- 路由 scope `/console`，独立的 `:console` pipeline
- OperatorUser 添加 `role` 字段(admin, operator)，默认 operator
- `Layouts.console` 侧边栏布局，根据 role 显示菜单
- 密码最短 6 位

### ✅ Step 2: 租户管理

```bash
mix phx.gen.live Tenants Tenant tenants name:string slug:string
```

租户是独立概念，不属于某个认证上下文。运营人员在 /console 创建租户、配置基本信息。租户管理LiveView放在运营后台路由下。

租户表格新增"用户"按钮，进入各租户用户管理（`/console/tenants/:id/users`）。

### ✅ Step 3: 租户用户认证

```bash
mix phx.gen.auth Accounts User users
```

User 添加 `belongs_to :tenant, Tenants.Tenant`（Ecto关联，迁移中不加数据库外键约束）。User 添加 `role` 字段（admin, member）。密码最短 6 位。

路由：`/login`、`/logout`、`/settings`。`Layouts.app` 用 `cond` 处理 operator scope 和 user scope。

### 🔲 Step 4: 邀请功能

创建 Invitation schema：

- 租户管理员输入邮箱 → 生成token → 发送邮件 → 用户点击链接 → 设置密码 → 创建User

### 🔲 Step 5: 租户上下文隔离

- Plug：根据当前用户获取其所属租户，assign到conn
- 路由隔离：租户相关的路由需要经过租户上下文Plug
- 所有租户数据的查询自动带上 tenant_id 过滤

### ✅ Step 6: 租户后台 LiveView

- /admin 路由，admin 角色用户可访问
- `Layouts.admin` 侧边栏布局（仪表盘 + 用户管理）
- 前台右上角 admin 用户显示"管理后台"按钮

### 📐 三层用户管理上下文

| Context | 用途 | 路由 |
|---------|------|------|
| `DeepBlue.Operator` | 内部用户自服务 | `/console/settings` |
| `DeepBlue.Console.TenantUsers` | 运营管理租户用户 | `/console/tenants/:id/users` |
| `DeepBlue.Admin.Users` | 租户管理自己用户 | `/admin/users` |
| `DeepBlue.Accounts` | 用户自服务 | `/settings` |

### ✅ 内部用户管理

- `/console/operators` 下管理内部用户，仅 admin 可访问
- 不能删除自己、不能改自己角色

---

## 第二阶段：模型平台

构建自己的模型服务平台，对外提供开放式模型调用API。不只是替换ReqLLM，而是完整的基础设施。

### Step 1: 模型注册与配置

- 模型管理：注册上游模型供应商（OpenAI、Anthropic、自研等）
- 模型配置：模型名称、能力标签、上下文窗口、计费标准
- 运营在 /console 管理模型

### Step 2: API Key 管理

- 为租户/开发者生成 API Key
- Key 权限控制（可访问的模型、速率限制）
- Key 管理界面（创建、吊销、查看用量）

### Step 3: 开放式模型调用API

- 对外提供 OpenAI 兼容的 HTTP API（/api/v1/chat/completions 等）
- 支持流式（SSE）和非流式调用
- API 鉴权（Bearer Token）
- 请求路由到对应的上游模型供应商

### Step 4: 计费系统

- 按token用量计费
- 租户维度的用量统计和账单
- 调用限额和预警

### Step 5: 接入文档

- API 文档页面（模型列表、参数说明、示例代码）
- SDK 使用指南

### Step 6: 内部模型调用模块

- 替换 ReqLLM，内部 Agent 也通过统一的模型平台调用
- 轻量级客户端，不依赖 LLMDB

---

## 第三阶段：Agent Core

Agent 不持久化，是纯运行时的配置包裹（system prompt + 模型选择 + 工具列表）。

**数据层（持久化）**：

- **Session** = 用户的对话通道，有 ID、用户、channel、标题、agent_config
- **Message** = 属于Session，对话记录
- agent_config 存在 Session 上，是对话创建时的配置快照

**运行时（进程状态）**：

- Agentic.Server 进程持有 Loop 状态，根据 agent_config 运行
- 通过 session_id 注册进程，可惰性启动
- **纯函数** = Agentic.Core.Loop，随时可从数据库重建状态

### ✅ Step 1: 重构 Core Msg/Cmd/State 体系

**三个核心数据结构**，各自独立模块，统一用 `type + payload` 建模：

- **`Agentic.Core.Msg`** — 输入 Loop 的消息
  - `Msg.user(content)` → `%Msg{type: :user, payload: content}`
  - `Msg.llm_response(response)` → `%Msg{type: :llm_response, payload: response}`
  - `Msg.tool_result(tool_use_id, result)` → `%Msg{type: :tool_result, payload: {tool_use_id, result}}`

- **`Agentic.Core.Cmd`** — Loop 输出的命令
  - `Cmd.call_llm(context, stream: bool)` → `:call_llm` 或 `:call_llm_stream`
  - `Cmd.exec_tool(tool_calls)` → `:exec_tool`
  - `Cmd.end_turn(response)` → `:end_turn`
  - `Cmd.error(reason)` → `:error`

- **`Agentic.Core.State`** — Loop 的状态
  - `context`（ReqLLM.Context）、`status`（:idle / :calling_llm / :calling_tools）、`id`、`stream`

**`Agentic.Core.Loop`** — 纯函数状态机：
- `init(id, prompt)` → `{state, []}`
- `step(state, msg)` → `{new_state, [cmd]}`，按 `state.status` + `msg.type` 模式匹配
- 状态转换：idle → calling_llm → calling_tools → calling_llm → ... → idle

**`Agentic.Server`** — GenServer 编排层：
- 在 callback 中构造 Msg 传入 Loop，匹配 Cmd 执行副作用
- ReqLLM 的 Context/Response/ToolCall 仅在 Loop 和 Server 内部使用，不暴露给上层

### Step 2: Chat Session schema

```bash
mix phx.gen.context Chat Session chat_sessions --binary-id user_id:references:users title:string agent_config:map
```

- Session 是用户的对话通道
- agent_config 存储创建时的agent配置快照（模型、system prompt、工具等），JSONB/map
- `id` 用 `binary_id`（UUID），不做对外暴露的自增ID
- `user_id` 做 `references(:users, on_delete: :delete_all)` 数据库外键（同一域，合理）
- Session 不在 User schema 上做 `has_many` 反向关联，避免上下文边界污染
- Chat context 用 `Accounts.Scope` 做权限隔离，PubSub topic 为 `"user:#{user_id}:chat_sessions"`
- `list_chat_sessions` 按 `inserted_at` 降序排列

### Step 2.1: Chat Session LiveView

**路由**：`/` 和 `/sessions/:id` 都放在 `live_session :require_authenticated_user`，强制登录，同一 live_session 内导航不刷新。

**首页（ChatLive.Index）**：
- 居中输入框，提交后创建 session（title = 用户输入内容），跳转到 `/sessions/:id`
- 使用 `Layouts.app`（max-w-2xl 居中布局）

**Session 详情页（ChatLive.Show）**：
- 使用 `Layouts.chat`（全高 flex 布局，header + 左侧边栏 + 右侧主内容）
- 左侧边栏：`stream(:sessions)` 显示历史对话列表，顶部"新对话"按钮直接创建 session（title="新对话"）
- 右侧：标题栏（含删除按钮）+ 消息区域 + 输入框
- 删除逻辑：删除后跳到列表中下一个 session，列表空则跳回首页
- 订阅 PubSub 实时更新 session 列表（created/updated/deleted）
- 用 `session_ids` assigns 追踪列表顺序，用于删除时找下一个 session

### Step 3: 三层数据设计

**第一层：完整消息记录（chat_messages）**

```bash
mix phx.gen.schema Chat Message chat_messages session_id:bigint role:string content:text metadata:map
```

- 所有消息的原始数据，不可变的数据基底
- role: user, assistant, tool_call, tool_result
- metadata: 工具调用参数、token用量等

**第二层：动态上下文（chat_contexts）**

```bash
mix phx.gen.schema Chat Context chat_contexts session_id:bigint messages:map token_count:integer
```

- 给大模型用的上下文，动态维护
- 包含经过裁剪/摘要后的消息列表
- token_count 跟踪当前上下文大小，用于控制截断策略
- 每次交互后更新，而非每次从完整记录重新构造

**第三层：界面对话历史（chat_ui_entries）**

```bash
mix phx.gen.schema Chat UIEntry chat_ui_entries session_id:bigint entry_type:string content:text display_metadata:map
```

- 给前端展示用的结构
- 可能和原始消息不同：一个tool_call+tool_result在UI上可能只展示一行摘要
- entry_type: user_message, assistant_message, tool_summary, system_notice 等

### Step 4: 修改 Agentic.Server

- 通过 session_id 注册进程（via Registry）
- LiveView mount时根据session_id查找或启动agent进程
- agent进程启动时从数据库加载 Context（动态上下文），重建Loop状态
- 用户发消息时：
  1. 持久化到 chat_messages（完整记录）
  2. 更新 chat_contexts（动态上下文，追加+可能裁剪）
  3. 更新 chat_ui_entries（界面展示）
  4. 喂给Loop → 执行commands
- 会话空闲超时后进程优雅退出，下次访问时从 chat_contexts 恢复

**当前实现（已完成，暂无消息持久化）**：

- `Agentic.Server.start_link(session_id)` — 按 session_id 注册到 Registry，key 为 `"session:#{session_id}"`
- `ensure_started(session_id)` — 查找已有进程或启动新的
- `get_state(session_id)` — 返回 State，用于判断是否 idle
- `send_message(session_id, msg)` — cast 消息给 agent
- `stop(session_id)` — 停止 agent 进程（race condition safe）
- Cmd 执行通过 `send(self(), {:exec, cmd})` 串行化
- `end_turn` 后自动 `send(self(), {:turn_completed})` 触发 dequeue

**流式推送机制**：
- `call_llm_stream` 命令在 Task 中执行，通过 `on_result` 和 `on_thinking` 回调推送 PubSub
- Topic：`"session:#{session_id}:stream"`
- 统一通过 `broadcast(session_id, msg)` 函数广播，不暴露 Loop 内部概念
- 广播协议见上方"UI广播协议"章节

**ChatLive.Show 集成**：
- mount 时 `ensure_started` 启动 agent + 订阅 PubSub stream topic
- `send_msg` 事件：追加用户消息到 assigns、发给 agent、设 loading 状态
- `thinking_delta`：实时拼接 thinking_text，loading 时展示 "思考中..." + spinner
- `stream_delta`：拼接 streaming_text，关闭 loading
- `agent_response`：把回复追加到 messages（带 thinking 字段），清空 streaming_text 和 thinking_text
- thinking 展示：流式阶段实时显示，完成后折叠为 DaisyUI collapse 组件，默认收起可展开
- 首条消息：Index 创建 session 时存到 `agent_config.initial_msg`，Show mount 时检查 agent idle 后发送并清空

**错误处理**：
- `call_stream` 返回 `{:error, _}` 时广播 `{:agent_error}`，前端显示错误消息
- `process_stream` 返回 `{:error, _}` 同理
- 不使用 try/rescue，全部用 case 匹配

**运行时状态追踪**：

- 当前正在生成的流式内容：追踪 partial response、正在执行的工具调用，实时推送状态给前端
- 消息队列：agent正在处理时用户又发来消息，需要排队。当前处理完成后依次处理队列中的消息，而非丢弃不阻塞

**消息队列（已完成）**：

- `Agentic.Core.State` 扩展 `pending_messages`（FIFO list）和 `current_msg` 字段
- `Loop.step` 当 `status != :idle` 时入队 `pending_messages`，返回 `{state, []}`
- `Loop.dequeue` 在 end_turn 后调用：有排队消息则 step 处理下一条，无则清空 `current_msg`
- Server 的 `handle_info {:turn_completed}` 调用 `Loop.dequeue` 触发下一条排队消息

**UI广播协议（已完成）**：

Server 通过统一的 `broadcast(session_id, msg)` 函数向 PubSub 推送面向 UI 语义的消息：

| 广播消息 | 含义 | UI行为 |
|---------|------|--------|
| `{:message_pending, msg}` | 用户消息已收到，排队等待 | 显示在输入框上方 pending 区域 |
| `{:message_started, msg}` | 消息开始被处理 | 移入主消息列表，显示 loading |
| `{:thinking_delta, text}` | 思考内容增量 | 实时拼接 thinking_text |
| `{:stream_delta, text}` | 回复内容增量 | 实时拼接 streaming_text |
| `{:agent_response, text}` | 一轮完整回复 | 追加 assistant 消息（含 thinking），清空流式状态 |
| `{:agent_error, error}` | 出错 | 追加错误消息，清空流式状态 |

LiveView 的 `send_msg` 只负责发到 Server + 清输入框，不管理消息列表，所有显示状态由 Server 广播驱动。

**LiveView UI（已完成）**：

- 时间线布局：所有消息自上而下，左侧图标+名称，右侧内容
- `message` 函数组件：统一渲染图标（hero-user/hero-sparkles）、名称（用户/AI Agent）、thinking折叠、内容
- pending 消息：在输入框上方单独渲染，带 spinner + 文字截断
- thinking：流式阶段实时显示，完成后折叠为可展开组件

**错误处理与重试**：

- LLM调用失败：自动重试（可配置次数），重试失败后通知用户
- 工具调用超时：超时阈值可配置，超时后返回错误结果给Agent让其决定下一步
- 流式中断：用户主动取消时，已生成内容保存为部分消息，进程回到idle状态
- 进程崩溃：通过Supervisor重启，从数据库恢复Context状态

### Step 5: 流式输出

- Agent回复通过 Phoenix.PubSub 推送给LiveView
- 前端实现打字效果的流式展示
- 工具调用过程也实时展示给用户

### Step 6: 工具调用

- 在 Agent config 中配置可用工具列表
- Agent可以调用工具并将结果返回对话
- 工具调用过程可视化展示

---

## 第四阶段：领域模型与知识库

知识库不是独立的文档/向量库，而是通过领域模型结构化沉淀下来的数据。

### 领域模型

- 租户可创建自己的领域模型（KV形式，类似Tana笔记软件）
- Agent可以按模型结构创建数据并沉淀
- 模型定义、数据录入、数据查询的LiveView界面

### 知识沉淀与审批

- **个人知识**：用户自己创建的数据，无需审批
- **企业知识库**：沉淀到企业级需要审批流程，保证质量
  - 用户提交知识到企业库 → 审批人审核 → 通过后入库
  - 审批人由租户管理员配置

### 知识检索（RAG）

- 结构化知识检索
- Agent对话中检索相关知识

---

## 第五阶段：Skill/工作流机制

- 实现类似当前对话的 plan→execute 模式
- Agent可以加载一个预定义的SOP/plan
- 按计划一边和用户沟通一边执行
- 积累的工作流可以模板化、复用

---

## 第六阶段：多模态

- 图片生成能力接入
- 前端图片展示打磨
- 其他多模态能力扩展

---

## 第七阶段：多Channel接入

- Channel 抽象层：统一的消息进出接口
- Web Channel：LiveView（已有）
- 飞书/钉钉/微信 Channel：通过 webhook 接收消息，通过 API 发送回复
- 跨Channel共享对话上下文（通过session_id关联）

---

## 第八阶段：后台任务

- 定时任务（Cron）：如定时报告、定期数据同步
- 异步任务：长时间运行的工具调用、批量处理
- 任务调度和管理界面
