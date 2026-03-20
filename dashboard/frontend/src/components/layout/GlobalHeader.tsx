import { useEffect, useRef, useState } from "react";
import { Bell, Circle } from "lucide-react";
import { useAuthStore } from "../../store/authStore";
import api from "../../hooks/useApi";
import type { GGStatus, GoNogo, ValidationSummary } from "../../types";
import { cn } from "../../lib/utils";
import GoNoBadge from "../GoNoBadge";

interface GGLight {
  name: string;
  status: GGStatus;
}

const GG_NAMES = ["EXT1", "PUMP1", "REP1"];

const GG_STATUS_CLASS: Record<GGStatus, string> = {
  RUNNING: "text-emerald-400",
  STOPPED: "text-amber-400",
  ABEND:   "text-red-400",
  UNKNOWN: "text-slate-500",
};

export default function GlobalHeader() {
  const { user, logout } = useAuthStore();
  const [currentPhase, setCurrentPhase] = useState<number>(0);
  const [goNogo, setGoNogo] = useState<GoNogo>("PENDING");
  const [ggLights] = useState<GGLight[]>(
    GG_NAMES.map((name) => ({ name, status: "UNKNOWN" as GGStatus }))
  );
  const [alertCount] = useState(0);
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Fetch current phase
  useEffect(() => {
    if (!user) return;
    api
      .get("/config")
      .then((res) => {
        const entry = (res.data as Array<{ key: string; value: string }>).find(
          (e) => e.key === "CURRENT_PHASE"
        );
        if (entry) setCurrentPhase(parseInt(entry.value) || 0);
      })
      .catch(() => {});
  }, [user]);

  // Poll validation summary for Go/No-Go (every 30 seconds)
  useEffect(() => {
    if (!user) return;

    const fetchGoNogo = () => {
      api
        .get<ValidationSummary>("/validation/summary")
        .then((res) => {
          setGoNogo(res.data.go_nogo);
        })
        .catch(() => {});
    };

    fetchGoNogo();
    pollingRef.current = setInterval(fetchGoNogo, 30_000);

    return () => {
      if (pollingRef.current !== null) {
        clearInterval(pollingRef.current);
        pollingRef.current = null;
      }
    };
  }, [user]);

  return (
    <header className="flex items-center justify-between px-4 py-2 bg-slate-800 border-b border-slate-700 shrink-0 z-10">
      {/* Left: title + Phase */}
      <div className="flex items-center gap-4">
        <div>
          <div className="text-sm font-bold text-white">Migration Dashboard</div>
          <div className="text-xs text-slate-400">AWS RDS → OCI DBCS</div>
        </div>
        <div className="px-3 py-1 rounded-full bg-blue-700 text-white text-xs font-bold tracking-wide">
          Phase {currentPhase}
        </div>
      </div>

      {/* Center: GG process lights */}
      <div className="flex items-center gap-5">
        {ggLights.map((gg) => (
          <div key={gg.name} className="flex items-center gap-1.5">
            <Circle
              className={cn(
                "w-2 h-2 fill-current shrink-0",
                GG_STATUS_CLASS[gg.status]
              )}
            />
            <span
              className={cn("text-xs font-mono", GG_STATUS_CLASS[gg.status])}
            >
              {gg.name}
            </span>
          </div>
        ))}
      </div>

      {/* Right: Go/No-Go badge + alerts + user */}
      <div className="flex items-center gap-3">
        <GoNoBadge goNogo={goNogo} size="sm" showLabel />

        <button className="relative text-slate-400 hover:text-white transition">
          <Bell className="w-5 h-5" />
          {alertCount > 0 && (
            <span className="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full text-[10px] flex items-center justify-center text-white font-bold">
              {alertCount}
            </span>
          )}
        </button>

        <div className="text-xs text-slate-400">
          <span className="text-white">{user?.username ?? "—"}</span>
          <span className="text-slate-500 ml-1">({user?.role ?? ""})</span>
        </div>

        <button
          onClick={logout}
          className="text-xs text-slate-400 hover:text-white px-2 py-1 rounded border border-slate-600 hover:border-slate-400 transition"
        >
          로그아웃
        </button>
      </div>
    </header>
  );
}
