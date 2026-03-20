import { useCallback, useEffect, useState } from "react";
import { Cog, Lock, Unlock, Check, X, RefreshCw } from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";
import type { ConfigEntry } from "../types";

export default function ConfigRegistry() {
  const [entries, setEntries] = useState<ConfigEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const r = await api.get<ConfigEntry[]>("/config");
      setEntries(r.data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const startEdit = (key: string, value: string | null) => {
    setEditing((prev) => ({ ...prev, [key]: value ?? "" }));
  };

  const cancelEdit = (key: string) => {
    setEditing((prev) => { const n = { ...prev }; delete n[key]; return n; });
  };

  const save = async (key: string) => {
    setSaving(key);
    try {
      await api.put(`/config/${key}`, { value: editing[key] });
      cancelEdit(key);
      await load();
    } finally {
      setSaving(null);
    }
  };

  const toggleLock = async (key: string, locked: boolean) => {
    if (locked) {
      // No unlock endpoint — inform user
      alert("잠금 해제는 관리자가 직접 DB에서 처리해야 합니다.");
      return;
    }
    await api.post(`/config/${key}/lock`);
    await load();
  };

  return (
    <div className="p-6 space-y-4 max-w-4xl">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Cog className="w-6 h-6 text-slate-400" />
          <h1 className="text-xl font-bold text-white">Config Registry</h1>
        </div>
        <button onClick={load} className="text-slate-400 hover:text-white">
          <RefreshCw className={cn("w-4 h-4", loading && "animate-spin")} />
        </button>
      </div>

      <div className="bg-slate-800 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-700 text-slate-400 text-xs">
              <th className="px-4 py-3 text-left w-64">키</th>
              <th className="px-4 py-3 text-left">값</th>
              <th className="px-4 py-3 text-left w-40">변경자</th>
              <th className="px-4 py-3 text-left w-40">변경 시각</th>
              <th className="px-4 py-3 text-center w-20">잠금</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700/50">
            {entries.map((entry) => {
              const isEditing = entry.key in editing;
              return (
                <tr key={entry.key} className="hover:bg-slate-700/30">
                  <td className="px-4 py-3 font-mono text-slate-300 text-xs">{entry.key}</td>
                  <td className="px-4 py-3">
                    {isEditing ? (
                      <div className="flex items-center gap-2">
                        <input
                          value={editing[entry.key]}
                          onChange={(e) =>
                            setEditing((prev) => ({ ...prev, [entry.key]: e.target.value }))
                          }
                          className="flex-1 bg-slate-700 border border-blue-500 rounded px-2 py-1 text-white text-sm focus:outline-none font-mono"
                          autoFocus
                          onKeyDown={(e) => {
                            if (e.key === "Enter") save(entry.key);
                            if (e.key === "Escape") cancelEdit(entry.key);
                          }}
                        />
                        <button
                          onClick={() => save(entry.key)}
                          disabled={saving === entry.key}
                          className="p-1 text-emerald-400 hover:text-emerald-300"
                        >
                          <Check className="w-4 h-4" />
                        </button>
                        <button onClick={() => cancelEdit(entry.key)} className="p-1 text-slate-400 hover:text-white">
                          <X className="w-4 h-4" />
                        </button>
                      </div>
                    ) : (
                      <button
                        onClick={() => !entry.locked && startEdit(entry.key, entry.value)}
                        disabled={entry.locked}
                        className={cn(
                          "font-mono text-sm text-left w-full truncate max-w-xs",
                          entry.locked
                            ? "text-slate-500 cursor-not-allowed"
                            : "text-white hover:text-blue-300 cursor-text"
                        )}
                        title={entry.locked ? "잠금됨" : "클릭하여 편집"}
                      >
                        {entry.value || <span className="text-slate-600">(empty)</span>}
                      </button>
                    )}
                  </td>
                  <td className="px-4 py-3 text-slate-500 text-xs">{entry.changed_by ?? "-"}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">
                    {entry.changed_at ? entry.changed_at.slice(0, 16).replace("T", " ") : "-"}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <button
                      onClick={() => toggleLock(entry.key, entry.locked)}
                      className={cn(
                        "p-1 rounded",
                        entry.locked
                          ? "text-amber-400 hover:text-amber-300"
                          : "text-slate-500 hover:text-slate-300"
                      )}
                      title={entry.locked ? "잠금됨" : "잠금"}
                    >
                      {entry.locked ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <p className="text-slate-600 text-xs">값 클릭 → 편집 · Enter 저장 · Esc 취소</p>
    </div>
  );
}
