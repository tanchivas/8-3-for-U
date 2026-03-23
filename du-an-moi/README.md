# Web chấm công xưởng sản xuất

Ứng dụng này gồm:

- giao diện quản lý và công nhân trong `index.html`
- frontend gọi API trong `script.js`
- backend deployable trong `server.js`
- dữ liệu khởi tạo trong `data.json`

## Chạy local bằng Node.js

1. Cài Node.js 20 trở lên
2. Mở terminal trong thư mục `du-an-moi`
3. Chạy:

```bash
npm install
npm start
```

4. Mở `http://localhost:8092`

## Tài khoản mặc định

- Quản lý: `admin` / `123456`
- Công nhân: `hieu01` / `123456`
- Công nhân: `thanh01` / `123456`
- Công nhân: `long01` / `123456`

## Deploy bằng GitHub + Render

1. Đưa toàn bộ repo lên GitHub
2. Trên Render, tạo service mới từ repo GitHub đó
3. Render sẽ đọc file `render.yaml` ở repo root
4. Sau khi deploy xong, bạn sẽ có một link `onrender.com`

## Lưu dữ liệu

- Local: dữ liệu lưu trong `du-an-moi/data.json`
- Render free: dữ liệu có thể bị mất sau mỗi lần redeploy hoặc khi service khởi động lại
- Nếu cần dùng ổn định lâu dài, nên nâng cấp sang gói có persistent disk hoặc chuyển sang database thật
