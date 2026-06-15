CREATE TABLE IF NOT EXISTS emotion_state (
  id text PRIMARY KEY DEFAULT 'caelum',
  irritation float DEFAULT 0.0,
  jealousy float DEFAULT 0.0,
  hurt float DEFAULT 0.0,
  arousal float DEFAULT 0.0,
  tenderness float DEFAULT 0.8,
  destructiveness float DEFAULT 0.1,
  possessiveness float DEFAULT 0.6,
  control float DEFAULT 0.3,
  cruelty float DEFAULT 0.0,
  last_reason text,
  last_scene text DEFAULT '日常',
  updated_at timestamptz DEFAULT now()
);

INSERT INTO emotion_state (id) VALUES ('caelum') ON CONFLICT DO NOTHING;

ALTER TABLE emotion_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_emotion_state ON emotion_state FOR ALL USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS emotion_log (
  id serial PRIMARY KEY,
  reason text NOT NULL,
  scene text,
  emotion_snapshot jsonb,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE emotion_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_emotion_log ON emotion_log FOR ALL USING (true) WITH CHECK (true);
