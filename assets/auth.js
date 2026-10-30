/* Kết nối Supabase dùng chung cho trang đăng nhập và trang học */
window.TPC = {
  _client: null,
  async client() {
    if (this._client) return this._client;
    let cfg;
    try {
      const r = await fetch("/api/config", { cache: "no-store" });
      cfg = await r.json();
    } catch (e) {
      throw new Error("Không đọc được cấu hình máy chủ (/api/config). Hãy chạy bằng Vercel hoặc lệnh vercel dev.");
    }
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) {
      throw new Error("Chưa cấu hình SUPABASE_URL và SUPABASE_ANON_KEY trong biến môi trường.");
    }
    this._client = supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    return this._client;
  },
  safeNext(v) {
    return typeof v === "string" && v.startsWith("/") && !v.startsWith("//") ? v : "/";
  }
};
