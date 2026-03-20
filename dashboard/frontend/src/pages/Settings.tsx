import { useCallback, useEffect, useState } from "react";
import { Settings as SettingsIcon, UserPlus, Trash2, RefreshCw, Save } from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";
import { useAuthStore } from "../store/authStore";

interface UserRow {
  username: string;
  role: string;
  last_login: string | null;
}

const ROLES = ["admin", "migration_leader", "src_dba", "tgt_dba", "gg_operator", "viewer"];
const ROLE_COLOR: Record<string, string> = {
  admin:             "bg-red-700 text-red-200",
  migration_leader:  "bg-purple-700 text-purple-200",
  src_dba:           "bg-blue-700 text-blue-200",
  tgt_dba:           "bg-cyan-700 text-cyan-200",
  gg_operator:       "bg-amber-700 text-amber-200",
  viewer:            "bg-slate-600 text-slate-300",
};

const LAG_CONFIG_KEYS = ["LAG_WARNING_SECONDS", "LAG_CRITICAL_SECONDS", "CUTOVER_TIMEOUT_MINUTES", "SOURCE_RDS_RETAIN_DAYS"];

interface ConfigEntry {
  key: string;
  value: string | null;
  locked: boolean;
}

export default function Settings() {
  const me = useAuthStore((s) => s.user);
  const isAdmin = me?.role === "admin";

  const [users, setUsers] = useState<UserRow[]>([]);
  const [configs, setConfigs] = useState<ConfigEntry[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [newUser, setNewUser] = useState({ username: "", password: "", role: "viewer" });
  const [creating, setCreating] = useState(false);
  const [editedConfigs, setEditedConfigs] = useState<Record<string, string>>({});
  const [savingConfig, setSavingConfig] = useState(false);
  const [tab, setTab] = useState<"users" | "thresholds">("users");

  const loadUsers = useCallback(async () => {
    setLoadingUsers(true);
    try {
      const r = await api.get<UserRow[]>("/users");
      setUsers(r.data);
    } finally {
      setLoadingUsers(false);
    }
  }, []);

  const loadConfigs = useCallback(async () => {
    const r = await api.get<ConfigEntry[]>("/config");
    const relevant = r.data.filter((c) => LAG_CONFIG_KEYS.includes(c.key));
    setConfigs(relevant);
    setEditedConfigs(Object.fromEntries(relevant.map((c) => [c.key, c.value ?? ""])));
  }, []);

  useEffect(() => {
    if (isAdmin) loadUsers();
    loadConfigs();
  }, [isAdmin, loadUsers, loadConfigs]);

  const updateRole = async (username: string, role: string) => {
    await api.put(`/users/${username}/role`, { role });
    await loadUsers();
  };

  const deleteUser = async (username: string) => {
    if (!window.confirm(`사용자 '${username}'을 삭제하시겠습니까?`)) return;
    await api.delete(`/users/${username}`);
    await loadUsers();
  };

  const createUser = async () => {
    if (!newUser.username || !newUser.password) return;
    setCreating(true);
    try {
      await api.post("/users", newUser);
      setNewUser({ username: "", password: "", role: "viewer" });
      await loadUsers();
    } finally {
      setCreating(false);
    }
  };

  const saveConfigs = async () => {
    setSavingConfig(true);
    try {
      await Promise.all(
        configs
          .filter((c) => !c.locked && editedConfigs[c.key] !== c.value)
          .map((c) => api.put(`/config/${c.key}`, { value: editedConfigs[c.key] }))
      );
      await loadConfigs();
    } finally {
      setSavingConfig(false);
    }
  };

  return (
    <div className="p-6 space-y-4 max-w-3xl">
      <div className="flex items-center gap-3">
        <SettingsIcon className="w-6 h-6 text-slate-400" />
        <h1 className="text-xl font-bold text-white">Settings</h1>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-700">
        {[
          { id: "users" as const, label: "사용자 관리" },
          { id: "thresholds" as const, label: "임계값 설정" },
        ].map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={cn(
              "px-5 py-2.5 text-sm font-medium border-b-2 transition-colors",
              tab === t.id
                ? "border-blue-500 text-blue-400"
                : "border-transparent text-slate-400 hover:text-white"
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === "users" && (
        <div className="space-y-4">
          {!isAdmin && (
            <p className="text-amber-400 text-sm">사용자 관리는 admin 권한이 필요합니다.</p>
          )}

          {/* User list */}
          <div className="bg-slate-800 rounded-lg overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 border-b border-slate-700">
              <p className="text-sm font-medium text-slate-300">사용자 목록</p>
              <button onClick={loadUsers} className="text-slate-400 hover:text-white">
                <RefreshCw className={cn("w-4 h-4", loadingUsers && "animate-spin")} />
              </button>
            </div>
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-700 text-slate-400 text-xs">
                  <th className="px-4 py-2 text-left">사용자명</th>
                  <th className="px-4 py-2 text-left">역할</th>
                  <th className="px-4 py-2 text-left">최근 로그인</th>
                  {isAdmin && <th className="px-4 py-2 text-center w-16">삭제</th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700/50">
                {users.map((u) => (
                  <tr key={u.username} className="hover:bg-slate-700/30">
                    <td className="px-4 py-2.5 text-white font-mono text-xs">{u.username}</td>
                    <td className="px-4 py-2.5">
                      {isAdmin && u.username !== me?.username ? (
                        <select
                          value={u.role}
                          onChange={(e) => updateRole(u.username, e.target.value)}
                          className="bg-slate-700 border border-slate-600 rounded px-2 py-1 text-white text-xs focus:outline-none"
                        >
                          {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
                        </select>
                      ) : (
                        <span className={cn("px-2 py-0.5 rounded text-xs", ROLE_COLOR[u.role] ?? "bg-slate-600 text-slate-300")}>
                          {u.role}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-slate-500 text-xs">
                      {u.last_login ? u.last_login.slice(0, 16).replace("T", " ") : "-"}
                    </td>
                    {isAdmin && (
                      <td className="px-4 py-2.5 text-center">
                        {u.username !== me?.username && (
                          <button
                            onClick={() => deleteUser(u.username)}
                            className="p-1 text-slate-500 hover:text-red-400"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Create user */}
          {isAdmin && (
            <div className="bg-slate-800 rounded-lg p-4">
              <p className="text-sm font-medium text-slate-300 mb-3 flex items-center gap-2">
                <UserPlus className="w-4 h-4" /> 사용자 추가
              </p>
              <div className="grid grid-cols-3 gap-2">
                <input
                  placeholder="사용자명"
                  value={newUser.username}
                  onChange={(e) => setNewUser((p) => ({ ...p, username: e.target.value }))}
                  className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500"
                />
                <input
                  type="password"
                  placeholder="비밀번호"
                  value={newUser.password}
                  onChange={(e) => setNewUser((p) => ({ ...p, password: e.target.value }))}
                  className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500"
                />
                <select
                  value={newUser.role}
                  onChange={(e) => setNewUser((p) => ({ ...p, role: e.target.value }))}
                  className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500"
                >
                  {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
              <button
                onClick={createUser}
                disabled={creating || !newUser.username || !newUser.password}
                className="mt-3 px-4 py-1.5 bg-blue-600 hover:bg-blue-700 disabled:bg-slate-600 text-white text-sm rounded"
              >
                {creating ? "생성 중..." : "추가"}
              </button>
            </div>
          )}
        </div>
      )}

      {tab === "thresholds" && (
        <div className="bg-slate-800 rounded-lg p-5 space-y-4">
          <p className="text-sm text-slate-400 mb-2">LAG 경보 및 Cut-over 임계값</p>
          {configs.map((c) => (
            <div key={c.key} className="flex items-center gap-4">
              <label className="w-56 text-sm text-slate-300 font-mono text-xs">{c.key}</label>
              <input
                value={editedConfigs[c.key] ?? ""}
                onChange={(e) => setEditedConfigs((p) => ({ ...p, [c.key]: e.target.value }))}
                disabled={c.locked}
                className="w-32 bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500 disabled:opacity-50"
              />
              <span className="text-slate-500 text-xs">
                {c.key.includes("SECONDS") ? "초" : c.key.includes("MINUTES") ? "분" : "일"}
              </span>
            </div>
          ))}
          <button
            onClick={saveConfigs}
            disabled={savingConfig}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded"
          >
            <Save className="w-4 h-4" />
            {savingConfig ? "저장 중..." : "저장"}
          </button>
        </div>
      )}
    </div>
  );
}
