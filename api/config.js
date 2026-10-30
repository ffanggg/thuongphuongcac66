// Trả cấu hình Supabase cho trình duyệt.
// Giá trị lấy từ biến môi trường (file .env khi chạy máy, hoặc Settings → Environment Variables trên Vercel).
// Chỉ đưa ra URL và khoá "anon" (khoá công khai). TUYỆT ĐỐI không đưa khoá service_role vào đây.
module.exports = (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.status(200).send(JSON.stringify({
    supabaseUrl: process.env.SUPABASE_URL || "",
    supabaseAnonKey: process.env.SUPABASE_ANON_KEY || ""
  }));
};
