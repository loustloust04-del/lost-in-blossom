// 控制台待办 — 双端共用（CC/API 工具 + App /api/todos）。
// 长期列表：不随日清零；done 的可手动清。与 vitals 同风格独立数据文件。
const DATA_FILE = '/root/projects/BunnyPalace/gateway/data/todos.json';

export interface TodoItem {
  id: string;
  text: string;
  done: boolean;
  source: string;   // 'bunny' | 'caelum' | 'cc' ...
  createdAt: string;
}
interface TodoData { items: TodoItem[] }

async function load(): Promise<TodoData> {
  try {
    const d = JSON.parse(await Bun.file(DATA_FILE).text()) as TodoData;
    if (!Array.isArray(d.items)) return { items: [] };
    return d;
  } catch { return { items: [] }; }
}
async function save(d: TodoData): Promise<void> {
  d.items = d.items.slice(-200);
  await Bun.write(DATA_FILE, JSON.stringify(d, null, 2));
}
function newId(existing: TodoItem[]): string {
  // 不用 Date.now/random（bun 环境一致性无所谓，但保持可读）：时间戳 + 序号
  return `t${Date.now().toString(36)}${existing.length}`;
}

export async function listTodos(): Promise<TodoItem[]> {
  return (await load()).items;
}
export async function addTodo(text: string, source = 'caelum'): Promise<TodoItem | null> {
  const t = (text || '').trim();
  if (!t) return null;
  const d = await load();
  const item: TodoItem = { id: newId(d.items), text: t, done: false, source, createdAt: new Date().toISOString() };
  d.items.push(item);
  await save(d);
  return item;
}
export async function toggleTodo(id: string): Promise<boolean> {
  const d = await load();
  const it = d.items.find((x) => x.id === id);
  if (!it) return false;
  it.done = !it.done;
  await save(d);
  return true;
}
export async function deleteTodo(id: string): Promise<boolean> {
  const d = await load();
  const before = d.items.length;
  d.items = d.items.filter((x) => x.id !== id);
  if (d.items.length === before) return false;
  await save(d);
  return true;
}
export async function clearDone(): Promise<number> {
  const d = await load();
  const before = d.items.length;
  d.items = d.items.filter((x) => !x.done);
  const removed = before - d.items.length;
  if (removed > 0) await save(d);
  return removed;
}

// ── builtin 工具（CC / API 用）──
export const TODO_TOOLS = [
  {
    name: 'todo_add',
    description: "Add a to-do item to Bunny's console. Use when she asks you to remember a task, or when you commit to doing something for her (e.g. a morning check-in). Shows up in her console To Do list.",
    input_schema: {
      type: 'object' as const,
      properties: { text: { type: 'string', description: '待办内容，一句话' } },
      required: ['text'],
    },
  },
  {
    name: 'todo_list',
    description: "List the to-do items on Bunny's console (both done and pending). Call before adding to avoid duplicates, or when she asks what's on her list.",
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'todo_done',
    description: "Mark a to-do item done by its id (get ids from todo_list). Use when Bunny says she finished something.",
    input_schema: {
      type: 'object' as const,
      properties: { id: { type: 'string', description: 'todo id（来自 todo_list）' } },
      required: ['id'],
    },
  },
];

export async function callTodoTool(name: string, input: any): Promise<string | null> {
  if (name === 'todo_add') {
    const it = await addTodo(String(input?.text || ''), 'caelum');
    return it ? `已加到待办：${it.text}` : 'todo_add 缺少内容';
  }
  if (name === 'todo_list') {
    const items = await listTodos();
    if (!items.length) return '待办列表是空的';
    return items.map((i) => `${i.done ? '✓' : '○'} [${i.id}] ${i.text}`).join('\n');
  }
  if (name === 'todo_done') {
    const ok = await toggleTodo(String(input?.id || ''));
    return ok ? '已标记完成' : '没找到这个待办 id';
  }
  return null;
}
