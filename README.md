# Deep Blue Agent

使用 [Jido](https://jido.run/) + [Durable Stream](https://durablestreams.com/) 开发的早期实验版 Agent

Durable Stream 用的是修改版的 [StreamKeeper](https://hex.pm/packages/streamkeeper)

Event 的设计大量借鉴 [Electric Agents](https://electric.ax/agents/)

Event 遵循 [Durable State](https://electric.ax/docs/streams/durable-state) 协议，所以也可以直接用 [Tanstack DB](https://tanstack.com/db/latest) 加上 [StreamDB](https://electric.ax/docs/streams/stream-db) 对接上流之后在 React 等前端应用中进行投影和消费

---

### 开发运行

#### 1. 安装 `Erlang` 和 `Elixir`

请参照 [官网](https://elixir-lang.org/install.html) 指南

#### 2. 安装 `Phoenix`

```console
mix archive.install hex phx_new
```

#### 3. 安装依赖并启动

```console
mix deps.get

iex -S mix phx.server
```

---

### 后续

- [ ] 上下文管理
- [ ] 容错
- [ ] 流的持久化
- [ ] 持久化记忆
- [ ] MCP
- [ ] Skill
- [ ] Ask User
- [ ] 知识库
- [ ] SubAgents
- [ ] 等等...

---

以前的手写 TEA 架构 Function Core 的设计详见 [ROADMAP.md](ROADMAP.md) 和 [PLAN.md](PLAN.md)。
