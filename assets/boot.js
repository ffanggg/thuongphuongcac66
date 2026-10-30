/* Kiểm tra đăng nhập rồi mới mở trang học.
   Chưa đăng nhập → chuyển về /login.
   Nối phần lưu tiến độ của trang học với Supabase (bảng progress, assignments, profiles). */
(async function boot() {
  const fail = msg => {
    const el = document.getElementById("gate");
    if (el) el.innerHTML = `<div class="gate-box"><b>Không mở được trang</b><p>${msg}</p><a href="/login">Về trang đăng nhập</a></div>`;
  };
  // BOOT_TIMEOUT: không treo mãi ở màn hình chờ
  const slow = setTimeout(() => fail("Kết nối tới máy chủ dữ liệu (Supabase) quá chậm hoặc bị chặn. Hãy kiểm tra mạng (thử tắt/bật VPN), rồi tải lại trang."), 15000);
  window.addEventListener("error", e => { if (document.getElementById("gate")) fail("Lỗi tải trang: " + (e.message || "không rõ")); });
  if (typeof supabase === "undefined") { clearTimeout(slow); return fail("Không tải được thư viện đăng nhập (assets/vendor/supabase.js)."); }
  let sb;
  try { sb = await TPC.client(); } catch (e) { clearTimeout(slow); return fail(e.message); }

  let session = null;
  try { ({ data: { session } } = await sb.auth.getSession()); } catch (e) { clearTimeout(slow); return fail("Không kiểm tra được đăng nhập: " + e.message); }
  clearTimeout(slow);
  if (!session) {
    location.replace("/login?next=" + encodeURIComponent(location.pathname + location.hash));
    return;
  }
  const user = session.user;
  sb.auth.onAuthStateChange(ev => { if (ev === "SIGNED_OUT") location.replace("/login"); });

  // Hồ sơ (tên, lớp, vai trò)
  let profile = null;
  {
    const { data } = await sb.from("profiles").select("id,email,full_name,class_name,role").eq("id", user.id).maybeSingle();
    profile = data || { id: user.id, email: user.email, full_name: user.user_metadata?.full_name || "", class_name: user.user_metadata?.class_name || "", role: "student" };
  }

  // Máy dùng chung: xoá tiến độ lưu tạm của tài khoản khác
  try {
    if (localStorage.getItem("tpc-uid") !== user.id) {
      localStorage.removeItem("tpc-me");
      localStorage.setItem("tpc-uid", user.id);
    }
  } catch (e) {}

  window.TPC_WEB = true;
  window.TPC_ME = { id: user.id, email: user.email, name: profile.full_name || user.email, role: profile.role };
  window.TPC_LOGOUT = async () => { await sb.auth.signOut(); location.replace("/login"); };

  /* ---------- Lớp nối dữ liệu (giữ nguyên giao diện code của trang học) ---------- */
  const TABLES = { progress: { t: "progress", key: "user_id" }, assign: { t: "assignments", key: "id" }, plans: { t: "plans", key: "id" } };
  const subs = { progress: [], assign: [], plans: [] };
  const dbError = error => ({ code: "invalid_argument", message: error.message });

  async function pull(name) {
    const { t, key } = TABLES[name];
    const { data, error } = await sb.from(t).select(`${key},data`);
    if (error) { console.warn(error); return; }
    const snap = { docs: (data || []).map(r => ({ id: r[key], exists: true, data: () => r.data })) };
    subs[name].forEach(cb => { try { cb(snap); } catch (e) { console.warn(e); } });
  }
  setInterval(() => { pull("progress"); pull("assign"); pull("plans"); }, 30000);

  let lastProfile = { n: profile.full_name || "", c: profile.class_name || "" };
  async function syncProfile(d) {
    const n = (d.nick || "").trim(), c = (d.cls || "").trim();
    if (n === lastProfile.n && c === lastProfile.c) return;
    lastProfile = { n, c };
    await sb.from("profiles").update({ full_name: n || null, class_name: c || null }).eq("id", user.id);
    window.TPC_ME.name = n || user.email;
  }

  const db = {
    collection(name) {
      const { t, key } = TABLES[name];
      return {
        doc(id) {
          return {
            async get() {
              const { data, error } = await sb.from(t).select("data").eq(key, id).maybeSingle();
              if (error) throw dbError(error);
              if (!data && name === "progress" && id === user.id) {
                // Lần đầu vào học: lấy tên, lớp từ lúc đăng ký
                const seed = { nick: profile.full_name || "", cls: profile.class_name || "" };
                return { id, exists: true, data: () => seed };
              }
              return { id, exists: !!data, data: () => data && data.data };
            },
            async set(d) {
              if (name === "progress") { d.email = user.email; await syncProfile(d); }
              const { error } = await sb.from(t).upsert({ [key]: id, data: d, ...(name === "progress" ? { updated_at: new Date().toISOString() } : {}) });
              if (error) throw dbError(error);
              pull(name);
            },
            async delete() {
              const { error } = await sb.from(t).delete().eq(key, id);
              if (error) throw dbError(error);
              pull(name);
            }
          };
        },
        async add(d) {
          const { data, error } = await sb.from(t).insert({ data: d }).select(key).single();
          if (error) throw dbError(error);
          pull(name);
          return { id: data[key] };
        },
        onSnapshot(cb) { subs[name].push(cb); pull(name); return () => { subs[name] = subs[name].filter(x => x !== cb); }; }
      };
    }
  };

  const userApi = {
    async id() { return user.id; },
    async isOwner() { return profile.role === "teacher"; },
    async canEdit() { return profile.role === "teacher"; },
    async can() { return true; },
    async profiles(ids) {
      const { data } = await sb.from("profiles").select("id,full_name,email").in("id", ids);
      const out = {};
      (data || []).forEach(p => { out[p.id] = { name: p.full_name || p.email || "" }; });
      return out;
    }
  };

  /* ---------- Lớp học: mã lớp kiểm tra trên máy chủ ---------- */
  const rpcError = error => new Error(/Mã lớp|code/i.test(error.message) ? "Mã lớp không đúng, em kiểm tra lại với cô nhé" : error.message);
  const classesApi = {
    async list() {
      const { data, error } = await sb.from("classes").select("id,data,created_at");
      if (error) throw error;
      return (data || []).map(r => ({ id: r.id, ...r.data, createdAt: r.data && r.data.createdAt || Date.parse(r.created_at) }));
    },
    async mine() {
      const { data } = await sb.from("class_members").select("class_id").eq("user_id", user.id);
      return (data || []).map(r => r.class_id);
    },
    async codes() {
      const { data, error } = await sb.rpc("class_codes");
      if (error) return {};
      const out = {}; (data || []).forEach(r => { out[r.id] = r.code; }); return out;
    },
    async members() {
      const { data } = await sb.from("class_members").select("class_id,user_id");
      const rows = data || [], ids = [...new Set(rows.map(r => r.user_id))], prof = {};
      if (ids.length) { const { data: ps } = await sb.from("profiles").select("id,full_name,email").in("id", ids); (ps || []).forEach(p => { prof[p.id] = p; }); }
      const out = {};
      rows.forEach(r => { const p = prof[r.user_id] || {}; (out[r.class_id] = out[r.class_id] || []).push({ id: r.user_id, name: p.full_name || p.email || "Học sinh", email: p.email || "" }); });
      return out;
    },
    async join(code) {
      const { data, error } = await sb.rpc("join_class", { p_code: code });
      if (error) throw rpcError(error);
      return data;
    },
    async leave(id) {
      const { error } = await sb.from("class_members").delete().eq("class_id", id).eq("user_id", user.id);
      if (error) throw error;
    },
    async kick(id, uid) {
      const { error } = await sb.from("class_members").delete().eq("class_id", id).eq("user_id", uid);
      if (error) throw error;
    },
    async save(id, data, code, isNew) {
      const row = { data }; if (code !== undefined) row.code = code;
      const { error } = isNew ? await sb.from("classes").insert({ id, ...row }) : await sb.from("classes").update(row).eq("id", id);
      if (error) throw error;
    },
    async remove(id) {
      const { error } = await sb.from("classes").delete().eq("id", id);
      if (error) throw error;
    }
  };

  window.TPC_CAPS = { classes: classesApi, use: async n => (n === "db" ? db : n === "user" ? userApi : null) };

  // Mở trang học
  const s = document.createElement("script");
  s.src = "/assets/app.js";
  s.onload = () => { document.body.classList.remove("locked"); const g = document.getElementById("gate"); if (g) g.remove(); };
  s.onerror = () => fail("Không tải được nội dung bài học (assets/app.js).");
  document.body.appendChild(s);
})();
