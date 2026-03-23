const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PORT = Number(process.env.PORT || 8092);
const HOST = process.env.HOST || "0.0.0.0";
const DATA_DIR = process.env.DATA_DIR || __dirname;
const DATA_FILE = path.join(DATA_DIR, "data.json");
const PUBLIC_DIR = __dirname;

const sessions = new Map();

const seedDb = {
  users: [
    { id: "u-admin", username: "admin", password: "123456", name: "Quản Lý Xưởng", role: "manager" },
    { id: "u-cn01", username: "hieu01", password: "123456", name: "Anh Hiếu", role: "worker" },
    { id: "u-cn02", username: "thanh01", password: "123456", name: "Anh Thành", role: "worker" },
    { id: "u-cn03", username: "long01", password: "123456", name: "Anh Long", role: "worker" },
  ],
  records: [],
};

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

ensureDb();

const server = http.createServer(async (req, res) => {
  try {
    const requestUrl = new URL(req.url, `http://${req.headers.host || "localhost"}`);
    const pathname = decodeURIComponent(requestUrl.pathname);

    if (pathname === "/healthz") {
      return sendJson(res, 200, { ok: true });
    }

    if (pathname.startsWith("/api/")) {
      return handleApi(req, res, requestUrl);
    }

    return handleStatic(res, pathname);
  } catch (error) {
    return sendJson(res, 500, { error: "Lỗi máy chủ nội bộ" });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}`);
});

function ensureDb() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(seedDb, null, 2), "utf8");
  }
}

function loadDb() {
  ensureDb();
  const raw = fs.readFileSync(DATA_FILE, "utf8");
  const db = JSON.parse(raw || "{}");
  if (!Array.isArray(db.users)) {
    db.users = [];
  }
  if (!Array.isArray(db.records)) {
    db.records = [];
  }
  return db;
}

function saveDb(db) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2), "utf8");
}

function send(res, statusCode, body, headers = {}) {
  const payload = Buffer.isBuffer(body) ? body : Buffer.from(body, "utf8");
  res.writeHead(statusCode, {
    "Content-Length": payload.length,
    Connection: "close",
    ...headers,
  });
  res.end(payload);
}

function sendJson(res, statusCode, data, headers = {}) {
  send(res, statusCode, JSON.stringify(data), {
    "Content-Type": "application/json; charset=utf-8",
    ...headers,
  });
}

function sendText(res, statusCode, text, headers = {}) {
  send(res, statusCode, text, {
    "Content-Type": "text/plain; charset=utf-8",
    ...headers,
  });
}

function handleStatic(res, pathname) {
  const relativePath = pathname === "/" ? "/index.html" : pathname;
  const fullPath = path.resolve(PUBLIC_DIR, `.${relativePath}`);

  if (!fullPath.startsWith(PUBLIC_DIR) || !fs.existsSync(fullPath) || !fs.statSync(fullPath).isFile()) {
    return sendText(res, 404, "Not Found");
  }

  const ext = path.extname(fullPath).toLowerCase();
  const contentType = contentTypes[ext] || "application/octet-stream";
  const fileBuffer = fs.readFileSync(fullPath);
  return send(res, 200, fileBuffer, { "Content-Type": contentType });
}

async function handleApi(req, res, requestUrl) {
  const db = loadDb();
  const method = req.method.toUpperCase();
  const pathname = requestUrl.pathname.toLowerCase();

  if (method === "POST" && pathname === "/api/login") {
    const body = await readJsonBody(req, res);
    if (!body) return;
    const user = db.users.find(
      (item) => item.username === String(body.username || "") && item.password === String(body.password || "")
    );

    if (!user) {
      return sendJson(res, 401, { error: "Sai tài khoản hoặc mật khẩu" });
    }

    const sessionId = crypto.randomUUID().replaceAll("-", "");
    sessions.set(sessionId, user.id);
    return sendJson(
      res,
      200,
      { user: { id: user.id, name: user.name, role: user.role, username: user.username } },
      { "Set-Cookie": `session_id=${sessionId}; Path=/; HttpOnly; SameSite=Lax` }
    );
  }

  if (method === "POST" && pathname === "/api/logout") {
    const sessionId = parseCookies(req).session_id;
    if (sessionId) {
      sessions.delete(sessionId);
    }
    return sendJson(res, 200, { ok: true }, { "Set-Cookie": "session_id=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax" });
  }

  if (method === "GET" && pathname === "/api/me") {
    const me = getSessionUser(req, db);
    if (!me) {
      return sendJson(res, 401, { error: "Bạn chưa đăng nhập" });
    }
    return sendJson(res, 200, { user: { id: me.id, name: me.name, role: me.role, username: me.username } });
  }

  if (method === "POST" && pathname === "/api/attendance/checkin") {
    const auth = requireRole(req, db, "worker");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const me = auth.user;
    const date = todayKey();
    let record = db.records.find((item) => item.workerId === me.id && item.date === date);

    if (!record) {
      record = { id: crypto.randomUUID().replaceAll("-", ""), workerId: me.id, date, checkIn: "", checkOut: "" };
      db.records.push(record);
    }

    if (record.checkIn) {
      return sendJson(res, 400, { error: "Bạn đã check-in hôm nay" });
    }

    record.checkIn = timeNow();
    saveDb(db);
    return sendJson(res, 200, { ok: true, record });
  }

  if (method === "POST" && pathname === "/api/attendance/checkout") {
    const auth = requireRole(req, db, "worker");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const me = auth.user;
    const date = todayKey();
    const record = db.records.find((item) => item.workerId === me.id && item.date === date);

    if (!record || !record.checkIn) {
      return sendJson(res, 400, { error: "Bạn chưa check-in" });
    }

    if (record.checkOut) {
      return sendJson(res, 400, { error: "Bạn đã check-out hôm nay" });
    }

    record.checkOut = timeNow();
    saveDb(db);
    return sendJson(res, 200, { ok: true, record });
  }

  if (method === "GET" && pathname === "/api/my-attendance/today") {
    const auth = requireRole(req, db, "worker");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const me = auth.user;
    const date = todayKey();
    const record =
      db.records.find((item) => item.workerId === me.id && item.date === date) ||
      { workerId: me.id, date, checkIn: "", checkOut: "" };
    return sendJson(res, 200, { record });
  }

  if (method === "GET" && pathname === "/api/workers") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const workers = db.users
      .filter((item) => item.role === "worker")
      .map((item) => ({ id: item.id, name: item.name, username: item.username }));
    return sendJson(res, 200, { workers });
  }

  if (method === "POST" && pathname === "/api/workers") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const body = await readJsonBody(req, res);
    if (!body) return;

    const name = String(body.name || "").trim();
    const username = String(body.username || "").trim();
    const password = String(body.password || "").trim();

    if (!name || !username || !password) {
      return sendJson(res, 400, { error: "Thiếu thông tin" });
    }

    if (db.users.some((item) => item.username.toLowerCase() === username.toLowerCase())) {
      return sendJson(res, 400, { error: "Tên đăng nhập đã tồn tại" });
    }

    const worker = {
      id: `u-${crypto.randomUUID().replaceAll("-", "").slice(0, 8)}`,
      username,
      password,
      name,
      role: "worker",
    };

    db.users.push(worker);
    saveDb(db);
    return sendJson(res, 201, { worker: { id: worker.id, name: worker.name, username: worker.username } });
  }

  if (method === "POST" && pathname === "/api/workers/update") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const body = await readJsonBody(req, res);
    if (!body) return;

    const worker = db.users.find((item) => item.id === String(body.id || "") && item.role === "worker");
    if (!worker) {
      return sendJson(res, 404, { error: "Không tìm thấy công nhân" });
    }

    const name = String(body.name || "").trim();
    const username = String(body.username || "").trim();
    const password = String(body.password || "").trim();

    if (!name || !username) {
      return sendJson(res, 400, { error: "Thiếu thông tin" });
    }

    if (db.users.some((item) => item.id !== worker.id && item.username.toLowerCase() === username.toLowerCase())) {
      return sendJson(res, 400, { error: "Tên đăng nhập đã tồn tại" });
    }

    worker.name = name;
    worker.username = username;
    if (password) {
      worker.password = password;
    }

    saveDb(db);
    return sendJson(res, 200, { ok: true });
  }

  if (method === "POST" && pathname === "/api/workers/delete") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const body = await readJsonBody(req, res);
    if (!body) return;

    const workerId = String(body.id || "").trim();
    const worker = db.users.find((item) => item.id === workerId && item.role === "worker");
    if (!worker) {
      return sendJson(res, 404, { error: "Không tìm thấy công nhân" });
    }

    db.users = db.users.filter((item) => item.id !== workerId);
    db.records = db.records.filter((item) => item.workerId !== workerId);
    saveDb(db);
    return sendJson(res, 200, { ok: true });
  }

  if (method === "POST" && pathname === "/api/attendance/upsert") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const body = await readJsonBody(req, res);
    if (!body) return;

    const workerId = String(body.workerId || "").trim();
    const date = String(body.date || "").trim();
    const checkIn = normalizeTime(String(body.checkIn || "").trim());
    const checkOut = normalizeTime(String(body.checkOut || "").trim());
    const recordId = String(body.id || "").trim();

    if (!workerId || !date) {
      return sendJson(res, 400, { error: "Thiếu công nhân hoặc ngày" });
    }

    const worker = db.users.find((item) => item.id === workerId && item.role === "worker");
    if (!worker) {
      return sendJson(res, 404, { error: "Không tìm thấy công nhân" });
    }

    let record = recordId
      ? db.records.find((item) => item.id === recordId)
      : db.records.find((item) => item.workerId === workerId && item.date === date);

    if (!record) {
      record = { id: crypto.randomUUID().replaceAll("-", ""), workerId, date, checkIn, checkOut };
      db.records.push(record);
    } else {
      record.workerId = workerId;
      record.date = date;
      record.checkIn = checkIn;
      record.checkOut = checkOut;
    }

    saveDb(db);
    return sendJson(res, 200, { ok: true, record });
  }

  if (method === "POST" && pathname === "/api/attendance/delete") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const body = await readJsonBody(req, res);
    if (!body) return;

    const recordId = String(body.id || "").trim();
    if (!recordId) {
      return sendJson(res, 400, { error: "Thiếu mã bản ghi" });
    }

    db.records = db.records.filter((item) => item.id !== recordId);
    saveDb(db);
    return sendJson(res, 200, { ok: true });
  }

  if (method === "GET" && pathname === "/api/stats/today") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });
    const date = todayKey();
    const workers = db.users.filter((item) => item.role === "worker");
    const records = db.records.filter((item) => item.date === date);
    return sendJson(res, 200, {
      stats: {
        date,
        totalWorkers: workers.length,
        checkedIn: records.filter((item) => item.checkIn).length,
        checkedOut: records.filter((item) => item.checkOut).length,
      },
    });
  }

  if (method === "GET" && pathname === "/api/attendance") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });

    const date = requestUrl.searchParams.get("date") || "";
    const month = requestUrl.searchParams.get("month") || "";
    const workerId = requestUrl.searchParams.get("workerId") || "";

    let rows = [...db.records];
    if (date) rows = rows.filter((item) => item.date === date);
    if (month) rows = rows.filter((item) => item.date.startsWith(month));
    if (workerId) rows = rows.filter((item) => item.workerId === workerId);

    return sendJson(res, 200, { records: mapRecords(db, rows) });
  }

  if (method === "GET" && pathname === "/api/attendance/export") {
    const auth = requireRole(req, db, "manager");
    if (auth.error) return sendJson(res, auth.error.status, { error: auth.error.message });

    const date = requestUrl.searchParams.get("date") || "";
    const month = requestUrl.searchParams.get("month") || "";
    const workerId = requestUrl.searchParams.get("workerId") || "";

    let rows = [...db.records];
    if (date) rows = rows.filter((item) => item.date === date);
    if (month) rows = rows.filter((item) => item.date.startsWith(month));
    if (workerId) rows = rows.filter((item) => item.workerId === workerId);

    if (month) {
      const csv = buildMonthlyCsv(db, rows, month, workerId);
      return send(res, 200, csv, {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename=bang-cong-thang-${month}.csv`,
      });
    }

    const mappedRows = mapRecords(db, rows);
    const lines = ["Ngày,CôngNhân,TàiKhoản,CheckIn,CheckOut,TrạngThái"];
    for (const row of mappedRows) {
      lines.push(
        [row.date, row.workerName, row.workerUsername, row.checkIn, row.checkOut, row.status]
          .map(quoteCsv)
          .join(",")
      );
    }
    return send(res, 200, lines.join("\n"), {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename=cham-cong-${todayKey()}.csv`,
    });
  }

  return sendJson(res, 404, { error: "Không tìm thấy API" });
}

function buildMonthlyCsv(db, rows, month, workerId) {
  const daysInMonth = getDaysInMonth(month);
  let workers = db.users.filter((item) => item.role === "worker");
  if (workerId) {
    workers = workers.filter((item) => item.id === workerId);
  }

  const header = ["CôngNhân", "TàiKhoản"];
  for (let day = 1; day <= daysInMonth; day += 1) {
    header.push(`Ngày_${String(day).padStart(2, "0")}`);
  }
  header.push("TổngCông", "ChưaRa", "Vắng");

  const lines = [header.join(",")];

  for (const worker of workers) {
    const workerRows = rows.filter((item) => item.workerId === worker.id);
    const recordsByDay = new Map(workerRows.map((item) => [Number(item.date.slice(-2)), item]));
    let presentCount = 0;
    let incompleteCount = 0;
    let absentCount = 0;
    const values = [quoteCsv(worker.name), quoteCsv(worker.username)];

    for (let day = 1; day <= daysInMonth; day += 1) {
      const record = recordsByDay.get(day);
      if (record && record.checkIn && record.checkOut) {
        presentCount += 1;
        values.push(quoteCsv("P"));
      } else if (record && record.checkIn) {
        incompleteCount += 1;
        values.push(quoteCsv("V"));
      } else {
        absentCount += 1;
        values.push(quoteCsv("-"));
      }
    }

    values.push(quoteCsv(String(presentCount)), quoteCsv(String(incompleteCount)), quoteCsv(String(absentCount)));
    lines.push(values.join(","));
  }

  return lines.join("\n");
}

function quoteCsv(value) {
  return `"${String(value ?? "").replaceAll('"', '""')}"`;
}

function mapRecords(db, rows) {
  return [...rows]
    .sort((a, b) => `${a.date}-${a.workerId}`.localeCompare(`${b.date}-${b.workerId}`))
    .map((record) => {
      const worker = db.users.find((item) => item.id === record.workerId);
      return {
        id: record.id,
        date: record.date,
        workerId: record.workerId,
        workerName: worker ? worker.name : record.workerId,
        workerUsername: worker ? worker.username : "",
        checkIn: record.checkIn || "",
        checkOut: record.checkOut || "",
        status: record.checkOut ? "Hoàn tất" : record.checkIn ? "Đang làm" : "Chưa vào",
      };
    });
}

function parseCookies(req) {
  const cookieHeader = req.headers.cookie || "";
  return cookieHeader.split(";").reduce((acc, item) => {
    const [key, ...rest] = item.trim().split("=");
    if (!key) return acc;
    acc[key] = rest.join("=");
    return acc;
  }, {});
}

function getSessionUser(req, db) {
  const sessionId = parseCookies(req).session_id;
  if (!sessionId || !sessions.has(sessionId)) {
    return null;
  }
  const userId = sessions.get(sessionId);
  return db.users.find((item) => item.id === userId) || null;
}

function requireRole(req, db, role) {
  const user = getSessionUser(req, db);
  if (!user) {
    return { error: { status: 401, message: "Bạn chưa đăng nhập" } };
  }
  if (user.role !== role) {
    return { error: { status: 403, message: "Không đủ quyền" } };
  }
  return { user };
}

function readJsonBody(req, res) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk.toString("utf8");
      if (raw.length > 1_000_000) {
        sendJson(res, 413, { error: "Payload quá lớn" });
        req.destroy();
        resolve(null);
      }
    });
    req.on("end", () => {
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        sendJson(res, 400, { error: "JSON không hợp lệ" });
        resolve(null);
      }
    });
    req.on("error", () => resolve(null));
  });
}

function todayKey() {
  const now = new Date();
  return formatLocalDate(now);
}

function timeNow() {
  const now = new Date();
  const hours = String(now.getHours()).padStart(2, "0");
  const minutes = String(now.getMinutes()).padStart(2, "0");
  const seconds = String(now.getSeconds()).padStart(2, "0");
  return `${hours}:${minutes}:${seconds}`;
}

function formatLocalDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function normalizeTime(value) {
  if (!value) return "";
  return value.length === 5 ? `${value}:00` : value;
}

function getDaysInMonth(monthValue) {
  const [yearText, monthText] = monthValue.split("-");
  return new Date(Number(yearText), Number(monthText), 0).getDate();
}
