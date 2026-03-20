import { useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, X } from "lucide-react";
import api from "../hooks/useApi";
import { useAuthStore } from "../store/authStore";

interface AlertItem {
  id: number;
  level: string;
  message: string;
  confirmed_by: string | null;
  confirmed_at: string | null;
  created_at: string;
}

export default function AlertBanner() {
  const token = useAuthStore((s) => s.token);
  const [alert, setAlert] = useState<AlertItem | null>(null);
  const [confirming, setConfirming] = useState(false);
  const audioRef = useRef<boolean>(false);

  const check = useCallback(async () => {
    if (!token) return;
    try {
      const r = await api.get<AlertItem[]>("/alerts", { params: { unconfirmed_only: "true", limit: "1" } });
      const critical = r.data.find((a) => a.level === "CRITICAL");
      setAlert(critical ?? null);
    } catch {
      // ignore - don't disrupt UI on poll failure
    }
  }, [token]);

  useEffect(() => {
    check();
    const id = setInterval(check, 15000);
    return () => clearInterval(id);
  }, [check]);

  // play beep when new critical alert appears
  useEffect(() => {
    if (!alert || audioRef.current) return;
    audioRef.current = true;
    try {
      const ctx = new AudioContext();
      [0, 0.3, 0.6].forEach((delay) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.frequency.value = 880;
        gain.gain.value = 0.3;
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(ctx.currentTime + delay);
        osc.stop(ctx.currentTime + delay + 0.2);
      });
    } catch {
      // AudioContext may be blocked
    }
  }, [alert]);

  useEffect(() => {
    if (!alert) audioRef.current = false;
  }, [alert]);

  if (!alert) return null;

  const confirm = async () => {
    setConfirming(true);
    try {
      await api.post(`/alerts/${alert.id}/confirm`);
      setAlert(null);
    } finally {
      setConfirming(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
      <div className="bg-red-900 border-2 border-red-500 rounded-xl p-6 max-w-md w-full mx-4 shadow-2xl animate-pulse-once">
        <div className="flex items-start gap-4">
          <div className="shrink-0 w-10 h-10 bg-red-600 rounded-full flex items-center justify-center">
            <AlertTriangle className="w-5 h-5 text-white" />
          </div>
          <div className="flex-1">
            <div className="flex items-center justify-between">
              <span className="text-red-300 text-xs font-bold uppercase tracking-wider">CRITICAL 알림</span>
              <span className="text-red-400 text-xs">{alert.created_at.slice(11, 19)} UTC</span>
            </div>
            <p className="text-white font-semibold mt-2">{alert.message}</p>
            <p className="text-red-300 text-sm mt-1">즉시 확인 후 조치가 필요합니다.</p>
          </div>
        </div>
        <button
          onClick={confirm}
          disabled={confirming}
          className="mt-5 w-full py-2.5 bg-red-600 hover:bg-red-700 text-white font-semibold rounded-lg text-sm transition-colors disabled:opacity-50"
        >
          {confirming ? "확인 중..." : "확인 (Acknowledge)"}
        </button>
      </div>
    </div>
  );
}
