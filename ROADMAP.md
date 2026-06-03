# Deep Blue Roadmap

## Phase 1: 租户和用户管理

- [x] 运营后台认证（/console）- 运营人员登录，角色权限（admin/operator）
- [x] 租户管理 - 运营人员创建和管理租户
- [x] 租户用户认证 - 用户登录，角色权限（admin/member），用户关联租户
- [ ] 邀请功能 - 租户管理员通过邮件邀请用户加入
- [ ] 租户上下文隔离 - 按租户隔离数据访问
- [x] 租户后台（/admin）- 租户管理员管理用户
- [x] 控制台管理租户用户 - 运营人员可在 /console 管理各租户用户
- [x] 内部用户管理 - admin 角色管理运营人员（/console/operators）

## Phase 2: 模型平台

- [ ] 模型注册与配置 - 管理上游供应商和模型
- [ ] API Key管理 - 为租户/开发者生成Key、权限控制
- [ ] 开放式模型调用API - OpenAI兼容的HTTP API，支持流式
- [ ] 计费系统 - 按token计费、用量统计、限额预警
- [ ] 接入文档 - API文档和SDK指南
- [ ] 内部模型调用模块 - 替换ReqLLM，统一调用链路

## Phase 3: Agent Core

- [x] Msg/Cmd/State建模 - Loop纯函数状态机，统一type+payload结构
- [x] Chat Session - 对话通道的数据模型和CRUD
- [x] Chat Session LiveView - 首页创建session、session详情页（侧边栏历史列表、删除跳转）
- [x] Agent接通 - Server按`session_id`注册、流式输出通过PubSub推送、thinking展示
- [x] Cmd执行消息化 - Server内部Cmd通过 `self()` 消息串行执行，便于扩展日志/监控/取消
- [x] 消息队列 - pending_messages排队，Loop.dequeue依次消费，不丢弃不阻塞
- [x] UI广播协议 - Server面向UI语义广播（message/message_queued/stream_delta/thinking_delta/response/error），不暴露Loop内部概念
- [x] LiveView UI重构 - 时间线布局，message函数组件，Server驱动UI状态
- [x] DurableStream+PubSub混合事件通道 - emit双写（DurableStream+PubSub带offset），Agent init加载DB历史到Stream，LiveView同步读Stream初始状态+PubSub实时消费，断连可追赶
- [x] 流式渲染优化 - delta事件走push_event+ColocatedHook直接操作DOM，不触发LiveView render；messages改用stream+offset作id；delta不更新assign
- [ ] 错误处理与重试 - LLM调用失败自动重试，重试失败通知用户
- [x] 三层数据设计 - DurableServer持久化context到EKV（ReqLLM.Context结构体）、session_history时间序列供UI渲染、DurableStream事件流同步回放
- [x] 进程生命周期 - DurableServer替代GenServer，状态自动持久化到EKV，崩溃可恢复
- [x] 会话清理 - 删除session时一并清理DurableStream和EKV持久化数据
- [ ] 工具调用 - 可配置工具列表、调用可视化

## Phase 4: 领域模型与知识库

- [ ] 领域模型 - 租户自建KV模型，Agent按模型沉淀数据
- [ ] 知识沉淀与审批 - 个人知识免审、企业知识审批流
- [ ] 知识检索（RAG） - 结构化检索，Agent关联知识

## Phase 5: Skill/工作流机制

- [ ] Plan→Execute模式 - Agent加载SOP，边沟通边执行
- [ ] 工作流模板化 - 积累的SOP可复用

## Phase 6: 多模态

- [ ] 图片生成接入
- [ ] 前端图片展示打磨

## Phase 7: 多Channel接入

- [ ] Channel抽象层 - 统一消息进出接口
- [ ] 飞书/钉钉/微信接入
- [ ] 跨Channel上下文共享

## Phase 8: 后台任务

- [ ] 定时任务（Cron）
- [ ] 异步任务
- [ ] 任务调度和管理界面
