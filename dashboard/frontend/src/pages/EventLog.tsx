import { useCallback, useEffect, useState } from "react";
import { Clock, Download, CheckCircle2, RefreshCw } from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";

interface EventItem {
  id: number;
  event_type: string;
  message: string;
  related_script: string | null;
  related_item: string | null;
  actor: string | null;
  created_at: string;
  confirmed_by: string | null;
  confirmed_at: string | null;
}

const TYPE_COLORS: Record<string, string> = {
  CUTOVER_START:   "bg-amber-600",
  ROLLBACK_START:  "bg-red-600",
  SCRIPT_RUN:      "bg-blue-600",
  SCRIPT_DONE:     "bg-emerald-600",
  SCRIPT_FAIL:     "bg-red-600",
  VALIDATION_UPDATE: "bg-purple-600",
  GG_ABEND:        "bg-red-700",
  SYSTEM:          "bg-slate-600",
};

function typeBadge(type: string) {
  const cls = TYPE_COLORS[type] ?? "bg-slate-600";
  return (
    <span className={cn("px-2 py-0.5 rounded text-xs font-medium text-white shrink-0", cls)}>
      {type.replace(/_/g, " ")}
    </span>
  );
}

export default function EventLog() {
  const today = new Date().toISOString().slice(0, 10);
  const [date, setDate] = useState(today);
  const [eventType, setEventType] = useState("");
  const [events, setEvents] = useState<EventItem[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string> = { limit: "200", date };
      if (eventType) params.event_type = eventType;
      const r = await api.get<EventItem[]>("/events", { params });
      setEvents(r.data);
    } finally {
      setLoading(false);
    }
  }, [date, eventType]);

  useEffect(() => { load(); }, [load]);

  const confirm = async (id: number) => {
    await api.post(`/events/${id}/confirm`);
    await load();
  };

  const exportPdf = async () => {
    const { jsPDF } = await import("jspdf");
    const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
    doc.setFontSize(14);
    doc.text(`Migration Event Log — ${date}`, 15, 15);
    doc.setFontSize(9);
    let y = 25;
    for (const ev of [...events].reverse()) {
      const time = ev.created_at.slice(11, 19);
      const line = `[${time}] [${ev.event_type}] ${ev.message}${ev.actor ? " (" + ev.actor + ")" : ""}`;
      const lines = doc.splitTextToSize(line, 180);
      if (y + lines.length * 5 > 285) {
        doc.addPage();
        y = 15;
      }
      doc.text(lines, 15, y);
      y += lines.length * 5 + 1;
    }
    doc.save(`event_log_${date}.pdf`);
  };

  const EVENT_TYPES = [
    "", "CUTOVER_START", "ROLLBACK_START", "SCRIPT_RUN", "SCRIPT_DONE",
    "SCRIPT_FAIL", "VALIDATION_UPDATE", "GG_ABEND", "SYSTEM"
  ];

  return (
    <div className="p-6 space-y-4 max-w-5xl">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Clock className="w-6 h-6 text-blue-400" />
          <h1 className="text-xl font-bold text-white">Event Log</h1>
          <span className="text-slate-400 text-sm">{events.length}건</span>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={load} className="p-2 text-slate-400 hover:text-white">
            <RefreshCw className={cn("w-4 h-4", loading && "animate-spin")} />
          </button>
          <button
            onClick={exportPdf}
            className="flex items-center gap-2 px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-white text-sm rounded"
          >
            <Download className="w-4 h-4" />
            PDF
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-3">
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500"
        />
        <select
          value={eventType}
          onChange={(e) => setEventType(e.target.value)}
          className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500"
        >
          {EVENT_TYPES.map((t) => (
            <option key={t} value={t}>{t || "전체 유형"}</option>
          ))}
        </select>
      </div>

      {/* Timeline */}
      {events.length === 0 ? (
        <div className="text-center py-16 text-slate-500">이벤트가 없습니다</div>
      ) : (
        <div className="relative">
          {/* vertical line */}
          <div className="absolute left-[7.5rem] top-0 bottom-0 w-px bg-slate-700" />
          <ul className="space-y-0">
            {[...events].reverse().map((ev) => (
              <li key={ev.id} className="flex gap-4 py-2">
                <div className="w-28 text-right shrink-0">
                  <p className="text-slate-400 text-xs font-mono">{ev.created_at.slice(11, 19)}</p>
                  {ev.actor && <p className="text-slate-600 text-xs truncate">{ev.actor}</p>}
                </div>
                {/* dot */}
                <div className="shrink-0 w-4 flex items-start justify-center pt-1">
                  <div className="w-2 h-2 rounded-full bg-blue-500 ring-2 ring-slate-900" />
                </div>
                <div className="flex-1 pb-3 border-b border-slate-800">
                  <div className="flex items-start gap-2 flex-wrap">
                    {typeBadge(ev.event_type)}
                    <p className="text-white text-sm">{ev.message}</p>
                  </div>
                  {(ev.related_script || ev.related_item) && (
                    <p className="text-slate-500 text-xs mt-0.5">
                      {[ev.related_script, ev.related_item].filter(Boolean).join(" · ")}
                    </p>
                  )}
                  {ev.confirmed_at ? (
                    <p className="text-slate-600 text-xs mt-1">
                      ✓ {ev.confirmed_by} 확인
                    </p>
                  ) : (
                    <button
                      onClick={() => confirm(ev.id)}
                      className="mt-1 flex items-center gap-1 text-xs text-slate-500 hover:text-emerald-400"
                    >
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      확인
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
