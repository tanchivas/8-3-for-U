const state = {
  me: null,
  workers: [],
  records: [],
  monthlyRecords: [],
  myRecord: null,
};

const authScreen = document.getElementById("authScreen");
const appScreen = document.getElementById("appScreen");
const loginForm = document.getElementById("loginForm");
const loginMessage = document.getElementById("loginMessage");
const usernameInput = document.getElementById("usernameInput");
const passwordInput = document.getElementById("passwordInput");
const logoutButton = document.getElementById("logoutButton");
const currentUserName = document.getElementById("currentUserName");
const currentUserRole = document.getElementById("currentUserRole");
const appTitle = document.getElementById("appTitle");
const todayLabel = document.getElementById("todayLabel");
const workerDateLabel = document.getElementById("workerDateLabel");
const managerView = document.getElementById("managerView");
const workerView = document.getElementById("workerView");
const statsGrid = document.getElementById("statsGrid");
const workerList = document.getElementById("workerList");
const workerCardTemplate = document.getElementById("workerCardTemplate");
const workerForm = document.getElementById("workerForm");
const workerFormTitle = document.getElementById("workerFormTitle");
const workerIdInput = document.getElementById("workerIdInput");
const workerNameInput = document.getElementById("workerNameInput");
const workerUsernameInput = document.getElementById("workerUsernameInput");
const workerPasswordInput = document.getElementById("workerPasswordInput");
const workerSubmitButton = document.getElementById("workerSubmitButton");
const resetWorkerFormButton = document.getElementById("resetWorkerFormButton");
const workerMessage = document.getElementById("workerMessage");
const attendanceForm = document.getElementById("attendanceForm");
const attendanceFormTitle = document.getElementById("attendanceFormTitle");
const attendanceRecordIdInput = document.getElementById("attendanceRecordIdInput");
const attendanceWorkerInput = document.getElementById("attendanceWorkerInput");
const attendanceDateInput = document.getElementById("attendanceDateInput");
const attendanceCheckInInput = document.getElementById("attendanceCheckInInput");
const attendanceCheckOutInput = document.getElementById("attendanceCheckOutInput");
const attendanceSubmitButton = document.getElementById("attendanceSubmitButton");
const resetAttendanceFormButton = document.getElementById("resetAttendanceFormButton");
const attendanceMessage = document.getElementById("attendanceMessage");
const managerDateInput = document.getElementById("managerDateInput");
const managerMonthInput = document.getElementById("managerMonthInput");
const managerWorkerFilter = document.getElementById("managerWorkerFilter");
const refreshRecordsButton = document.getElementById("refreshRecordsButton");
const refreshMonthButton = document.getElementById("refreshMonthButton");
const exportMonthButton = document.getElementById("exportMonthButton");
const exportButton = document.getElementById("exportButton");
const managerAttendanceTable = document.getElementById("managerAttendanceTable");
const monthlyAttendanceHead = document.getElementById("monthlyAttendanceHead");
const monthlyAttendanceTable = document.getElementById("monthlyAttendanceTable");
const workerGreeting = document.getElementById("workerGreeting");
const workerStats = document.getElementById("workerStats");
const checkInButton = document.getElementById("checkInButton");
const checkOutButton = document.getElementById("checkOutButton");
const workerActionMessage = document.getElementById("workerActionMessage");

init();

async function init() {
  const today = getTodayKey();
  todayLabel.textContent = formatFullDate(today);
  workerDateLabel.textContent = formatFullDate(today);
  managerDateInput.value = today;
  managerMonthInput.value = today.slice(0, 7);
  attendanceDateInput.value = today;
  bindEvents();
  await restoreSession();
}

function bindEvents() {
  loginForm.addEventListener("submit", handleLogin);
  logoutButton.addEventListener("click", handleLogout);
  workerForm.addEventListener("submit", handleWorkerSubmit);
  resetWorkerFormButton.addEventListener("click", resetWorkerForm);
  attendanceForm.addEventListener("submit", handleAttendanceSubmit);
  resetAttendanceFormButton.addEventListener("click", resetAttendanceForm);
  refreshRecordsButton.addEventListener("click", loadManagerData);
  refreshMonthButton.addEventListener("click", loadMonthlyData);
  managerDateInput.addEventListener("change", loadManagerData);
  managerMonthInput.addEventListener("change", loadMonthlyData);
  managerWorkerFilter.addEventListener("change", loadManagerData);
  exportButton.addEventListener("click", exportRecords);
  exportMonthButton.addEventListener("click", exportMonthlyRecords);
  checkInButton.addEventListener("click", () => handleWorkerAction("checkin"));
  checkOutButton.addEventListener("click", () => handleWorkerAction("checkout"));
}

async function restoreSession() {
  try {
    const data = await api("/api/me");
    state.me = data.user;
    renderShell();
    await loadRoleData();
  } catch {
    showAuth();
  }
}

async function handleLogin(event) {
  event.preventDefault();
  setMessage(loginMessage, "Đang đăng nhập...", false);

  try {
    const data = await api("/api/login", {
      method: "POST",
      body: {
        username: usernameInput.value.trim(),
        password: passwordInput.value,
      },
    });

    state.me = data.user;
    loginForm.reset();
    renderShell();
    await loadRoleData();
    setMessage(loginMessage, "", false);
  } catch (error) {
    setMessage(loginMessage, error.message, true);
  }
}

async function handleLogout() {
  try {
    await api("/api/logout", { method: "POST" });
  } catch {
  }

  state.me = null;
  state.workers = [];
  state.records = [];
  state.monthlyRecords = [];
  state.myRecord = null;
  showAuth();
}

async function loadRoleData() {
  if (!state.me) {
    return;
  }

  if (state.me.role === "manager") {
    await loadManagerData();
    await loadMonthlyData();
  } else {
    await loadWorkerData();
  }
}

async function loadManagerData() {
  try {
    const [workersData, statsData, recordsData] = await Promise.all([
      api("/api/workers"),
      api("/api/stats/today"),
      api(getAttendanceUrl()),
    ]);

    state.workers = workersData.workers || [];
    state.records = recordsData.records || [];
    renderManagerStats(statsData.stats);
    renderWorkers();
    renderWorkerFilter();
    renderAttendanceWorkerOptions();
    renderManagerRecords();
  } catch (error) {
    setMessage(workerMessage, error.message, true);
  }
}

async function loadMonthlyData() {
  try {
    const data = await api(getMonthlyAttendanceUrl());
    state.monthlyRecords = data.records || [];
    renderMonthlyRecords();
  } catch (error) {
    setMessage(workerMessage, error.message, true);
  }
}

async function loadWorkerData() {
  try {
    const data = await api("/api/my-attendance/today");
    state.myRecord = data.record;
    renderWorkerRecord();
  } catch (error) {
    setMessage(workerActionMessage, error.message, true);
  }
}

async function handleWorkerSubmit(event) {
  event.preventDefault();
  const isEdit = Boolean(workerIdInput.value);
  setMessage(workerMessage, isEdit ? "Đang cập nhật công nhân..." : "Đang thêm công nhân...", false);

  try {
    const payload = {
      id: workerIdInput.value,
      name: workerNameInput.value.trim(),
      username: workerUsernameInput.value.trim(),
      password: workerPasswordInput.value.trim(),
    };

    await api(isEdit ? "/api/workers/update" : "/api/workers", {
      method: "POST",
      body: payload,
    });

    resetWorkerForm();
    setMessage(workerMessage, isEdit ? "Đã cập nhật công nhân." : "Đã thêm công nhân.", false);
    await loadManagerData();
    await loadMonthlyData();
  } catch (error) {
    setMessage(workerMessage, error.message, true);
  }
}

async function handleAttendanceSubmit(event) {
  event.preventDefault();
  const isEdit = Boolean(attendanceRecordIdInput.value);
  setMessage(attendanceMessage, isEdit ? "Đang cập nhật bản ghi..." : "Đang lưu bản ghi...", false);

  try {
    await api("/api/attendance/upsert", {
      method: "POST",
      body: {
        id: attendanceRecordIdInput.value,
        workerId: attendanceWorkerInput.value,
        date: attendanceDateInput.value,
        checkIn: attendanceCheckInInput.value,
        checkOut: attendanceCheckOutInput.value,
      },
    });

    resetAttendanceForm();
    setMessage(attendanceMessage, isEdit ? "Đã cập nhật bản ghi." : "Đã lưu bản ghi.", false);
    await loadManagerData();
    await loadMonthlyData();
  } catch (error) {
    setMessage(attendanceMessage, error.message, true);
  }
}

async function handleWorkerAction(action) {
  const actionLabel = action === "checkin" ? "Check-in" : "Check-out";
  setMessage(workerActionMessage, `${actionLabel} đang được xử lý...`, false);

  try {
    await api(`/api/attendance/${action}`, { method: "POST" });
    await loadWorkerData();
    setMessage(workerActionMessage, `${actionLabel} thành công.`, false);
  } catch (error) {
    setMessage(workerActionMessage, error.message, true);
  }
}

function renderShell() {
  if (!state.me) {
    showAuth();
    return;
  }

  authScreen.classList.add("hidden");
  appScreen.classList.remove("hidden");
  currentUserName.textContent = state.me.name;
  currentUserRole.textContent = state.me.role === "manager" ? "Quản lý" : "Công nhân";

  if (state.me.role === "manager") {
    appTitle.textContent = "Bảng điều khiển quản lý";
    managerView.classList.remove("hidden");
    workerView.classList.add("hidden");
  } else {
    appTitle.textContent = "Khu vực công nhân";
    workerView.classList.remove("hidden");
    managerView.classList.add("hidden");
    workerGreeting.textContent = `Xin chào ${state.me.name}`;
  }
}

function showAuth() {
  authScreen.classList.remove("hidden");
  appScreen.classList.add("hidden");
  setMessage(loginMessage, "", false);
  setMessage(workerMessage, "", false);
  setMessage(attendanceMessage, "", false);
  setMessage(workerActionMessage, "", false);
}

function renderManagerStats(stats) {
  const items = [
    { label: "Tổng công nhân", value: stats.totalWorkers || 0 },
    { label: "Đã check-in", value: stats.checkedIn || 0 },
    { label: "Đã check-out", value: stats.checkedOut || 0 },
    { label: "Chưa vào ca", value: Math.max((stats.totalWorkers || 0) - (stats.checkedIn || 0), 0) },
  ];

  statsGrid.innerHTML = items
    .map(
      (item) => `
        <article class="stat-card">
          <p class="stat-label">${item.label}</p>
          <p class="stat-value">${item.value}</p>
        </article>
      `
    )
    .join("");
}

function renderWorkers() {
  workerList.innerHTML = "";

  if (!state.workers.length) {
    workerList.innerHTML = `<p class="form-message">Chưa có công nhân nào.</p>`;
    return;
  }

  state.workers.forEach((worker) => {
    const fragment = workerCardTemplate.content.cloneNode(true);
    fragment.querySelector(".worker-name").textContent = worker.name;
    fragment.querySelector(".worker-meta").textContent = worker.username;

    fragment.querySelector(".worker-edit").addEventListener("click", () => {
      workerIdInput.value = worker.id;
      workerNameInput.value = worker.name;
      workerUsernameInput.value = worker.username;
      workerPasswordInput.value = "";
      workerFormTitle.textContent = "Sửa công nhân";
      workerSubmitButton.textContent = "Lưu thay đổi";
      setMessage(workerMessage, `Đang sửa ${worker.name}.`, false);
    });

    fragment.querySelector(".worker-delete").addEventListener("click", async () => {
      if (!confirm(`Xóa công nhân ${worker.name}?`)) {
        return;
      }

      try {
        await api("/api/workers/delete", {
          method: "POST",
          body: { id: worker.id },
        });
        resetWorkerForm();
        await loadManagerData();
        await loadMonthlyData();
        setMessage(workerMessage, "Đã xóa công nhân.", false);
      } catch (error) {
        setMessage(workerMessage, error.message, true);
      }
    });

    workerList.appendChild(fragment);
  });
}

function renderWorkerFilter() {
  const currentValue = managerWorkerFilter.value;
  managerWorkerFilter.innerHTML =
    `<option value="">Tất cả công nhân</option>` +
    state.workers.map((worker) => `<option value="${worker.id}">${worker.name}</option>`).join("");
  managerWorkerFilter.value = currentValue;
}

function renderAttendanceWorkerOptions() {
  const currentValue = attendanceWorkerInput.value;
  attendanceWorkerInput.innerHTML = state.workers
    .map((worker) => `<option value="${worker.id}">${worker.name}</option>`)
    .join("");
  attendanceWorkerInput.value = currentValue || state.workers[0]?.id || "";
}

function renderManagerRecords() {
  if (!state.records.length) {
    managerAttendanceTable.innerHTML = `
      <tr>
        <td colspan="7">Chưa có dữ liệu chấm công theo bộ lọc hiện tại.</td>
      </tr>
    `;
    return;
  }

  managerAttendanceTable.innerHTML = state.records
    .map(
      (record) => `
        <tr>
          <td>${record.date || "-"}</td>
          <td>${record.workerName || "-"}</td>
          <td>${record.workerUsername || "-"}</td>
          <td>${record.checkIn || "-"}</td>
          <td>${record.checkOut || "-"}</td>
          <td><span class="status-badge ${getStatusClass(record.status)}">${record.status || "-"}</span></td>
          <td>
            <div class="worker-actions">
              <button type="button" class="ghost small record-edit" data-id="${record.id}">Sửa</button>
              <button type="button" class="ghost small danger-button record-delete" data-id="${record.id}">Xóa</button>
            </div>
          </td>
        </tr>
      `
    )
    .join("");

  managerAttendanceTable.querySelectorAll(".record-edit").forEach((button) => {
    button.addEventListener("click", () => {
      const record = state.records.find((item) => item.id === button.dataset.id);
      if (!record) {
        return;
      }

      attendanceRecordIdInput.value = record.id;
      attendanceWorkerInput.value = record.workerId;
      attendanceDateInput.value = record.date;
      attendanceCheckInInput.value = record.checkIn ? record.checkIn.slice(0, 5) : "";
      attendanceCheckOutInput.value = record.checkOut ? record.checkOut.slice(0, 5) : "";
      attendanceFormTitle.textContent = "Sửa bản ghi chấm công";
      attendanceSubmitButton.textContent = "Lưu thay đổi";
      setMessage(attendanceMessage, `Đang sửa bản ghi ngày ${record.date}.`, false);
      attendanceForm.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  });

  managerAttendanceTable.querySelectorAll(".record-delete").forEach((button) => {
    button.addEventListener("click", async () => {
      if (!confirm("Xóa bản ghi chấm công này?")) {
        return;
      }

      try {
        await api("/api/attendance/delete", {
          method: "POST",
          body: { id: button.dataset.id },
        });
        resetAttendanceForm();
        await loadManagerData();
        await loadMonthlyData();
        setMessage(attendanceMessage, "Đã xóa bản ghi.", false);
      } catch (error) {
        setMessage(attendanceMessage, error.message, true);
      }
    });
  });
}

function renderWorkerRecord() {
  const record = state.myRecord || {};
  const items = [
    { label: "Ngày", value: record.date || getTodayKey() },
    { label: "Check-in", value: record.checkIn || "--:--:--" },
    { label: "Check-out", value: record.checkOut || "--:--:--" },
  ];

  workerStats.innerHTML = items
    .map(
      (item) => `
        <article class="stat-card">
          <p class="stat-label">${item.label}</p>
          <p class="stat-value">${item.value}</p>
        </article>
      `
    )
    .join("");

  checkInButton.disabled = Boolean(record.checkIn);
  checkOutButton.disabled = !record.checkIn || Boolean(record.checkOut);
}

function getAttendanceUrl() {
  const params = new URLSearchParams();
  if (managerDateInput.value) {
    params.set("date", managerDateInput.value);
  }
  if (managerWorkerFilter.value) {
    params.set("workerId", managerWorkerFilter.value);
  }
  return `/api/attendance?${params.toString()}`;
}

function getMonthlyAttendanceUrl() {
  const params = new URLSearchParams();
  if (managerMonthInput.value) {
    params.set("month", managerMonthInput.value);
  }
  return `/api/attendance?${params.toString()}`;
}

function exportRecords() {
  const params = new URLSearchParams();
  if (managerDateInput.value) {
    params.set("date", managerDateInput.value);
  }
  if (managerWorkerFilter.value) {
    params.set("workerId", managerWorkerFilter.value);
  }
  window.location.href = `/api/attendance/export?${params.toString()}`;
}

function exportMonthlyRecords() {
  const params = new URLSearchParams();
  if (managerMonthInput.value) {
    params.set("month", managerMonthInput.value);
  }
  window.location.href = `/api/attendance/export?${params.toString()}`;
}

function renderMonthlyRecords() {
  const monthValue = managerMonthInput.value || getTodayKey().slice(0, 7);
  const [yearText, monthText] = monthValue.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  const daysInMonth = new Date(year, month, 0).getDate();
  const dayHeaders = Array.from({ length: daysInMonth }, (_, index) => index + 1);

  const workerRows = state.workers.map((worker) => {
    const recordsByDay = new Map(
      state.monthlyRecords
        .filter((record) => record.workerId === worker.id)
        .map((record) => [Number(record.date.slice(-2)), record])
    );

    let presentCount = 0;
    let incompleteCount = 0;
    let absentCount = 0;

    const dayCells = dayHeaders
      .map((day) => {
        const record = recordsByDay.get(day);
        if (record && record.checkIn) {
          if (record.checkOut) {
            presentCount += 1;
          } else {
            incompleteCount += 1;
          }
          const label = record.checkOut ? "P" : "V";
          const markClass = record.checkOut ? "mark-p" : "mark-v";
          return `<td class="day-cell" title="${record.checkIn}${record.checkOut ? ` - ${record.checkOut}` : ""}"><span class="day-mark ${markClass}">${label}</span></td>`;
        }

        absentCount += 1;
        return `<td class="day-cell"><span class="day-mark mark-dot">-</span></td>`;
      })
      .join("");

    return `
      <tr>
        <td class="summary-cell">
          <strong>${worker.name}</strong><br>
          <span class="worker-meta">${worker.username}</span><br>
          <span class="worker-meta">Công: ${presentCount} | Chưa ra: ${incompleteCount} | Vắng: ${absentCount}</span>
        </td>
        ${dayCells}
        <td class="day-cell">${presentCount}</td>
        <td class="day-cell">${incompleteCount}</td>
        <td class="day-cell">${absentCount}</td>
      </tr>
    `;
  });

  monthlyAttendanceHead.innerHTML = `
    <tr>
      <th>Công nhân</th>
      ${dayHeaders.map((day) => `<th class="day-cell">${String(day).padStart(2, "0")}</th>`).join("")}
      <th class="day-cell">Công</th>
      <th class="day-cell">Chưa ra</th>
      <th class="day-cell">Vắng</th>
    </tr>
  `;

  if (!workerRows.length) {
    monthlyAttendanceTable.innerHTML = `<tr><td colspan="${daysInMonth + 4}">Chưa có công nhân để lập bảng tháng.</td></tr>`;
    return;
  }

  monthlyAttendanceTable.innerHTML = workerRows.join("");
}

function resetWorkerForm() {
  workerForm.reset();
  workerIdInput.value = "";
  workerFormTitle.textContent = "Thêm công nhân";
  workerSubmitButton.textContent = "Thêm công nhân";
  setMessage(workerMessage, "", false);
}

function resetAttendanceForm() {
  attendanceForm.reset();
  attendanceRecordIdInput.value = "";
  attendanceDateInput.value = managerDateInput.value || getTodayKey();
  attendanceFormTitle.textContent = "Thêm hoặc sửa bản ghi";
  attendanceSubmitButton.textContent = "Lưu bản ghi";
  renderAttendanceWorkerOptions();
  setMessage(attendanceMessage, "", false);
}

function setMessage(element, text, isError) {
  element.textContent = text;
  element.style.color = isError ? "var(--danger)" : "var(--muted)";
}

function getStatusClass(status) {
  return {
    "Đang làm": "status-dang-lam",
    "Hoàn tất": "status-hoan-tat",
    "Chưa vào": "status-chua-vao",
  }[status] || "status-dang-lam";
}

function getTodayKey() {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function formatFullDate(dateString) {
  return new Intl.DateTimeFormat("vi-VN", {
    weekday: "long",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(new Date(dateString));
}

async function api(url, options = {}) {
  const response = await fetch(url, {
    method: options.method || "GET",
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    credentials: "include",
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json") ? await response.json() : null;

  if (!response.ok) {
    throw new Error(payload?.error || "Yêu cầu thất bại");
  }

  return payload;
}
