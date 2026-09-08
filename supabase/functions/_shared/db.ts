import postgres from "npm:postgres@3.4.5";

let sql: ReturnType<typeof postgres> | null = null;

export function db() {
  if (sql) {
    return sql;
  }
  const url = Deno.env.get("SUPABASE_DB_URL");
  if (!url) {
    throw new Error("SUPABASE_DB_URL is not configured");
  }
  sql = postgres(url, { prepare: false, max: 1 });
  return sql;
}
