# Thượng Phương Các · website ôn tập HSK (Vercel + Supabase)

## Thư mục gồm những gì

| File | Công dụng |
|---|---|
| `index.html` | Trang học. Chưa đăng nhập thì tự chuyển về `/login`. |
| `login.html` | Đăng nhập, đăng ký (họ tên, lớp, email, mật khẩu), quên mật khẩu. |
| `assets/app.js` | Toàn bộ nội dung bài học và giao diện (HSK 1 Bài 1–15, HSK 2 Bài 1–15, HSK 3 Bài 1–20, HSK 4 Bài 1–20, từ vựng HSK 1–5). |
| `assets/boot.js` | Kiểm tra đăng nhập, nối việc lưu tiến độ với Supabase. |
| `assets/auth.js` | Tạo kết nối Supabase từ cấu hình máy chủ. |
| `api/config.js` | Đọc `SUPABASE_URL` và `SUPABASE_ANON_KEY` từ biến môi trường, đưa cho trình duyệt. |
| `supabase/schema.sql` | Tạo bảng hồ sơ, tiến độ, bài tập, lớp học, mã lớp và quyền truy cập. |
| `.env.example` | Mẫu file biến môi trường. |

Khoá bảo mật không nằm trong code. Chỉ có 2 biến môi trường, đặt ở file `.env` (máy cá nhân) hoặc trong cài đặt của Vercel.

## Bước 1 · Tạo Supabase

1. Vào https://supabase.com → **New project**.
2. Mở **SQL Editor** → **New query**, dán toàn bộ nội dung `supabase/schema.sql` → **Run**.
3. Vào **Project Settings → API**, chép 2 giá trị:
   - **Project URL** → dùng cho `SUPABASE_URL`
   - **anon public** key → dùng cho `SUPABASE_ANON_KEY`
   (Không dùng khoá `service_role`.)
4. Vào **Authentication → URL Configuration**:
   - **Site URL**: địa chỉ website trên Vercel, ví dụ `https://thuongphuongcac.vercel.app`
   - **Redirect URLs**: thêm `https://thuongphuongcac.vercel.app/login`
5. (Tuỳ chọn) **Authentication → Providers → Email**: tắt **Confirm email** nếu muốn học sinh đăng ký xong vào học được ngay, không cần xác nhận qua email.

## Bước 2 · Đưa lên Vercel

1. Đưa thư mục này lên GitHub (file `.env` đã được bỏ qua, không bị đẩy lên).
2. Vào https://vercel.com → **Add New → Project** → chọn repository.
   - Framework Preset: **Other**. Không cần Build Command.
3. Trước khi bấm Deploy, mở **Environment Variables** và thêm:
   - `SUPABASE_URL` = Project URL
   - `SUPABASE_ANON_KEY` = anon public key
4. Bấm **Deploy**.

Nếu đổi biến môi trường sau này: vào **Settings → Environment Variables**, sửa, rồi **Redeploy**.

## Bước 3 · Cấp quyền giáo viên cho cô

1. Mở website, bấm **Đăng ký**, tạo tài khoản của cô.
2. Vào Supabase → **SQL Editor**, chạy (thay email):
   ```sql
   update public.profiles set role = 'teacher' where email = 'email-cua-co@gmail.com';
   ```
3. Đăng xuất rồi đăng nhập lại. Cô sẽ thấy mục **Giám sát học sinh** và khung **Giao bài mới**.

## Lớp học và mã lớp

- Khi chạy `schema.sql`, Supabase tạo sẵn 4 lớp: **HSK1-3 (2-4-6)**, **HSK1-5 (3-5-7)**, **HSK4 (5,6,CN)**, **HSK1-5 (7,CN)**, mỗi lớp một mã ngẫu nhiên.
- Cô vào mục **Lớp học** để xem mã, sao chép mã gửi học sinh, đổi mã mới, chọn khoá học mở cho lớp, giao bài cho lớp và cho học sinh rời lớp.
- Học sinh vào **Lớp học** → nhập mã. Mã được kiểm tra trên máy chủ (hàm `join_class`); học sinh không đọc được mã của các lớp.
- Khoá học nào không thuộc lớp của học sinh sẽ hiện khoá 🔒 và yêu cầu nhập mã lớp.
- Nếu cô đã chạy `schema.sql` bản cũ: chỉ cần chạy lại toàn bộ file mới, các lệnh đều chạy lại được an toàn.

## Quản lý học sinh

- Học sinh tự đăng ký bằng họ tên, lớp, email, mật khẩu.
- Mục **Giám sát học sinh** hiện tên, email, lớp, bài đang học, điểm từng kỹ năng, lần hoạt động gần nhất.
- Xem toàn bộ danh sách tài khoản: Supabase → **Table Editor → profiles**.
- Xoá hoặc khoá tài khoản: Supabase → **Authentication → Users**.
- Học sinh đã đăng nhập xem được bảng xếp hạng (tên và điểm của cả lớp). Chỉ giáo viên được giao bài, xoá bài và xem trang Giám sát.

## Chạy thử trên máy

```bash
npm i -g vercel
cp .env.example .env      # rồi điền 2 giá trị thật
vercel dev                # mở http://localhost:3000
```
Mở thẳng file `index.html` bằng trình duyệt sẽ không chạy được, vì trang cần `/api/config`.
