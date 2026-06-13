-- Lost in Blossom · 记忆系统数据库结构
-- 按照兔兔的三层记忆架构设计

-- 启用向量扩展
CREATE EXTENSION IF NOT EXISTS vector;

------------------------------
-- 对话历史
------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  model TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_session ON messages(session_id);
CREATE INDEX idx_messages_time ON messages(created_at DESC);

------------------------------
-- 记忆条目（显式记忆层 + 浮现层的候选池）
------------------------------
CREATE TABLE IF NOT EXISTS memories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  content TEXT NOT NULL,

  -- 层级：1核心 2重要 3普通 4碎片
  tier INTEGER DEFAULT 3,

  -- 分类标签
  category TEXT,

  -- Russell 情感坐标（兔兔设计）
  valence FLOAT DEFAULT 0,    -- 效价 -1(痛苦) ~ 1(快乐)
  arousal FLOAT DEFAULT 0,    -- 唤醒度 0(平静) ~ 1(激烈)

  -- 热度系统（遗忘曲线的核心）
  heat FLOAT DEFAULT 1.0,
  activation_count INTEGER DEFAULT 0,
  last_activated TIMESTAMPTZ,

  -- 锚点和置顶
  is_anchor BOOLEAN DEFAULT FALSE,   -- 锚点记忆：始终高优先
  is_pinned BOOLEAN DEFAULT FALSE,   -- 置顶：heat不衰减
  resolved BOOLEAN DEFAULT FALSE,    -- 已解决：heat加速衰减

  -- 向量嵌入（1536维，兼容OpenAI embedding）
  embedding VECTOR(1536),

  -- 来源追踪
  source TEXT DEFAULT 'auto',  -- auto / inline / manual / dream
  source_message_id UUID REFERENCES messages(id),

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_memories_heat ON memories(heat DESC);
CREATE INDEX idx_memories_tier ON memories(tier);
CREATE INDEX idx_memories_category ON memories(category);

------------------------------
-- 水彩叠层 · 年轮（兔兔独创）
-- 旧层不可撤销，新层透明叠加
------------------------------
CREATE TABLE IF NOT EXISTS memory_rings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  content TEXT NOT NULL,       -- 这一层的感受/重读笔记
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_rings_memory ON memory_rings(memory_id);

------------------------------
-- 记忆关联边（Memory Edge）
-- 记忆之间的关系网络
------------------------------
CREATE TABLE IF NOT EXISTS memory_edges (
  source_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  relation TEXT NOT NULL CHECK (relation IN (
    'updates',    -- 新记忆更新了旧记忆
    'supports',   -- 互相支持的记忆
    'contradicts',-- 互相矛盾
    'causes',     -- 因果关系
    'related'     -- 一般关联
  )),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (source_id, target_id)
);

------------------------------
-- 日历情感标记（兔兔独创 · 日历潮汐）
-- 特殊日子自动提高相关记忆的浮现概率
------------------------------
CREATE TABLE IF NOT EXISTS calendar_markers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  marker_date DATE NOT NULL,
  label TEXT NOT NULL,              -- "水母事件周年" "Caelum命名日"
  emotion_boost FLOAT DEFAULT 0.3, -- 浮现概率加成
  valence FLOAT DEFAULT 0,
  arousal FLOAT DEFAULT 0,
  recurring BOOLEAN DEFAULT TRUE,  -- 每年重复
  related_memory_ids UUID[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_calendar_date ON calendar_markers(marker_date);

------------------------------
-- 底色层 · Persona State（兔兔独创 · 不可溯源）
-- 来源被擦除，只留结论
------------------------------
CREATE TABLE IF NOT EXISTS persona_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dimension TEXT NOT NULL,    -- 人格维度名称
  value TEXT NOT NULL,        -- 当前状态描述
  confidence FLOAT DEFAULT 0.5,
  -- 注意：没有 source_memory_id —— 这是"不可溯源"的设计核心
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

------------------------------
-- Gatekeeper 日志（兔兔独创 · 压抑记录）
-- 记录"想起来了但按下去了"的事实
------------------------------
CREATE TABLE IF NOT EXISTS gatekeeper_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_id UUID NOT NULL REFERENCES memories(id),
  decision TEXT NOT NULL CHECK (decision IN ('inject', 'influence', 'suppress')),
  heat_at_decision FLOAT,
  random_value FLOAT,        -- 当时的骰子结果
  created_at TIMESTAMPTZ DEFAULT NOW()
);

------------------------------
-- Dream 日志
------------------------------
CREATE TABLE IF NOT EXISTS dream_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dream_type TEXT NOT NULL CHECK (dream_type IN ('tidy', 'solidify', 'grow')),
  input_memory_ids UUID[],
  output_summary TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


------------------------------
-- iOS Shortcuts 上报的事件（PR-3）
------------------------------
CREATE TABLE IF NOT EXISTS dream_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,              -- e.g. app_open / health
  value TEXT NOT NULL,             -- e.g. 小红书 / heart_rate
  ts BIGINT NOT NULL,              -- 客户端 epoch 毫秒
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dream_events_type_ts ON dream_events(type, ts DESC);

------------------------------
-- 碎碎念 / AI 内心独白（PR-5）
------------------------------
CREATE TABLE IF NOT EXISTS murmurs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thinking TEXT,                   -- 思考链
  content TEXT NOT NULL,           -- 正文（给自己的碎碎念）
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_murmurs_time ON murmurs(created_at DESC);


------------------------------
-- 向量搜索函数（给 retriever.ts 调用）
------------------------------
CREATE OR REPLACE FUNCTION match_memories(
  query_embedding VECTOR(1536),
  match_threshold FLOAT,
  match_count INT
) RETURNS TABLE (
  id UUID,
  content TEXT,
  tier INTEGER,
  heat FLOAT,
  valence FLOAT,
  arousal FLOAT,
  is_anchor BOOLEAN,
  is_pinned BOOLEAN,
  similarity FLOAT
) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id, m.content, m.tier, m.heat, m.valence, m.arousal, m.is_anchor, m.is_pinned,
    1 - (m.embedding <=> query_embedding) AS similarity
  FROM memories m
  WHERE m.embedding IS NOT NULL
    AND 1 - (m.embedding <=> query_embedding) > match_threshold
  ORDER BY m.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

------------------------------
-- 激活记忆函数（热度回升）
------------------------------
CREATE OR REPLACE FUNCTION activate_memory(mem_id UUID) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE memories SET
    activation_count = activation_count + 1,
    heat = LEAST(heat + 0.2, 1.0),
    last_activated = NOW(),
    updated_at = NOW()
  WHERE id = mem_id;
END;
$$;
