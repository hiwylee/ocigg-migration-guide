import { useCallback, useEffect, useRef, useState } from "react";
import { ChevronDown, ChevronRight, CheckCircle2, AlertTriangle, XCircle, Clock } from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";
import GoNoBadge from "../components/GoNoBadge";
import type { GoNogo } from "../types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type VStatus = "PASS" | "WARN" | "FAIL" | "PENDING";
type VPriority = "HIGH" | "MEDIUM" | "LOW";

interface ValidationItem {
  id: number;
  domain: string;
  item_no: number;
  item_name: string;
  priority: VPriority;
  status: VStatus;
  note: string | null;
  assignee: string | null;
  verified_at: string | null;
  verified_by: string | null;
}

interface DomainSummary {
  domain: string;
  total: number;
  pass_count: number;
  warn_count: number;
  fail_count: number;
  pending_count: number;
}

interface SummaryData {
  total: number;
  pass_count: number;
  warn_count: number;
  fail_count: number;
  pending_count: number;
  go_nogo: GoNogo;
  domain_summary: DomainSummary[];
}

// ---------------------------------------------------------------------------
// Style helpers
// ---------------------------------------------------------------------------

const STATUS_STYLE: Record<VStatus, string> = {
  PASS:    "bg-emerald-600 text-white",
  WARN:    "bg-amber-600 text-white",
  FAIL:    "bg-red-600 text-white",
  PENDING: "bg-slate-600 text-slate-300",
};

const STATUS_ICON: Record<VStatus, React.ReactNode> = {
  PASS:    <CheckCircle2 className="w-3.5 h-3.5" />,
  WARN:    <AlertTriangle className="w-3.5 h-3.5" />,
  FAIL:    <XCircle className="w-3.5 h-3.5" />,
  PENDING: <Clock className="w-3.5 h-3.5" />,
};

const PRIORITY_STYLE: Record<VPriority, string> = {
  HIGH:   "bg-red-600 text-white",
  MEDIUM: "bg-amber-600 text-white",
  LOW:    "bg-slate-600 text-slate-300",
};

const STATUS_BUTTONS: VStatus[] = ["PASS", "WARN", "FAIL", "PENDING"];

// ---------------------------------------------------------------------------
// StatusBadge
// ---------------------------------------------------------------------------

function StatusBadge({ status }: { status: VStatus }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold",
        STATUS_STYLE[status]
      )}
    >
      {STATUS_ICON[status]}
      {status}
    </span>
  );
}

// ---------------------------------------------------------------------------
// PriorityBadge
// ---------------------------------------------------------------------------

function PriorityBadge({ priority }: { priority: VPriority }) {
  return (
    <span
      className={cn(
        "inline-flex items-center px-2 py-0.5 rounded text-xs font-bold",
        PRIORITY_STYLE[priority]
      )}
    >
      {priority}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Domain progress card
// ---------------------------------------------------------------------------

function DomainCard({
  summary,
  onClick,
}: {
  summary: DomainSummary;
  onClick: () => void;
}) {
  const pct = summary.total > 0 ? Math.round((summary.pass_count / summary.total) * 100) : 0;
  const label = summary.domain.replace(/^\d+_/, "").replace(/_/g, " ");

  return (
    <button
      onClick={onClick}
      className="flex flex-col gap-2 bg-slate-800 border border-slate-700 rounded-lg p-4 hover:bg-slate-700 transition text-left w-full"
    >
      <div className="text-xs font-bold text-slate-300 truncate">{summary.domain}</div>
      <div className="text-[10px] text-slate-500 truncate">{label}</div>

      {/* Progress bar */}
      <div className="w-full h-2 bg-slate-700 rounded-full overflow-hidden">
        <div
          className="h-full bg-emerald-500 rounded-full transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
      <div className="text-xs text-slate-400">{pct}% PASS</div>

      {/* Counts */}
      <div className="flex gap-2 flex-wrap text-[11px]">
        <span className="text-emerald-400">P:{summary.pass_count}</span>
        <span className="text-amber-400">W:{summary.warn_count}</span>
        <span className="text-red-400">F:{summary.fail_count}</span>
        <span className="text-slate-500">-:{summary.pending_count}</span>
      </div>
    </button>
  );
}

// ---------------------------------------------------------------------------
// ItemRow
// ---------------------------------------------------------------------------

interface ItemRowProps {
  item: ValidationItem;
  onUpdate: (id: number, fields: Partial<Pick<ValidationItem, "status" | "note" | "assignee">>) => Promise<void>;
}

function ItemRow({ item, onUpdate }: ItemRowProps) {
  const [showNote, setShowNote] = useState(false);
  const [noteVal, setNoteVal] = useState(item.note ?? "");
  const [assigneeVal, setAssigneeVal] = useState(item.assignee ?? "");
  const [saving, setSaving] = useState(false);
  const assigneeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleStatus = async (s: VStatus) => {
    if (s === item.status) return;
    setSaving(true);
    await onUpdate(item.id, { status: s });
    setSaving(false);
  };

  const handleNoteSave = async () => {
    await onUpdate(item.id, { note: noteVal });
    setShowNote(false);
  };

  const handleAssigneeChange = (val: string) => {
    setAssigneeVal(val);
    if (assigneeTimer.current) clearTimeout(assigneeTimer.current);
    assigneeTimer.current = setTimeout(() => {
      onUpdate(item.id, { assignee: val });
    }, 800);
  };

  const fmtDate = (iso: string | null) => {
    if (!iso) return "—";
    try {
      return new Date(iso).toLocaleString("ko-KR", {
        month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit",
      });
    } catch {
      return iso;
    }
  };

  return (
    <div
      className={cn(
        "border-b border-slate-700/50 bg-slate-800/50 hover:bg-slate-800 transition",
        item.status === "FAIL" && "border-l-2 border-l-red-500",
        item.status === "WARN" && "border-l-2 border-l-amber-500"
      )}
    >
      <div className="flex items-start gap-3 px-4 py-2.5">
        {/* No + Name */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-slate-500 text-xs font-mono w-6 shrink-0">
              {item.item_no}
            </span>
            <span className="text-slate-200 text-sm">{item.item_name}</span>
            <PriorityBadge priority={item.priority} />
          </div>
          {/* Note preview */}
          {item.note && !showNote && (
            <div className="mt-1 text-xs text-slate-500 ml-8 truncate">
              {item.note}
            </div>
          )}
          {/* Note textarea */}
          {showNote && (
            <div className="mt-2 ml-8 flex gap-2">
              <textarea
                className="flex-1 bg-slate-700 border border-slate-600 rounded px-2 py-1 text-xs text-slate-200 resize-none h-16 focus:outline-none focus:border-blue-500"
                value={noteVal}
                onChange={(e) => setNoteVal(e.target.value)}
                placeholder="메모 입력..."
              />
              <div className="flex flex-col gap-1">
                <button
                  onClick={handleNoteSave}
                  className="px-2 py-1 bg-blue-600 hover:bg-blue-500 text-white text-xs rounded"
                >
                  저장
                </button>
                <button
                  onClick={() => { setShowNote(false); setNoteVal(item.note ?? ""); }}
                  className="px-2 py-1 bg-slate-600 hover:bg-slate-500 text-slate-300 text-xs rounded"
                >
                  취소
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Assignee */}
        <input
          className="w-24 bg-slate-700 border border-slate-600 rounded px-2 py-1 text-xs text-slate-200 focus:outline-none focus:border-blue-500 shrink-0"
          placeholder="담당자"
          value={assigneeVal}
          onChange={(e) => handleAssigneeChange(e.target.value)}
        />

        {/* Status buttons */}
        <div className="flex gap-1 shrink-0">
          {STATUS_BUTTONS.map((s) => (
            <button
              key={s}
              disabled={saving}
              onClick={() => handleStatus(s)}
              className={cn(
                "px-2 py-1 rounded text-[11px] font-semibold transition",
                item.status === s
                  ? STATUS_STYLE[s]
                  : "bg-slate-700 text-slate-400 hover:bg-slate-600"
              )}
            >
              {s === "PENDING" ? "—" : s}
            </button>
          ))}
        </div>

        {/* Note toggle */}
        <button
          onClick={() => setShowNote((v) => !v)}
          className="text-slate-500 hover:text-slate-300 text-xs shrink-0"
          title="메모 편집"
        >
          {item.note ? "📝" : "✏️"}
        </button>

        {/* Verified info */}
        <div className="text-right text-[10px] text-slate-500 shrink-0 w-28">
          {item.verified_by && (
            <div className="text-slate-400">{item.verified_by}</div>
          )}
          <div>{fmtDate(item.verified_at)}</div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// DomainAccordion
// ---------------------------------------------------------------------------

interface DomainAccordionProps {
  domain: string;
  items: ValidationItem[];
  defaultOpen: boolean;
  onUpdate: (id: number, fields: Partial<Pick<ValidationItem, "status" | "note" | "assignee">>) => Promise<void>;
}

function DomainAccordion({ domain, items, defaultOpen, onUpdate }: DomainAccordionProps) {
  const [open, setOpen] = useState(defaultOpen);

  const pass = items.filter((i) => i.status === "PASS").length;
  const fail = items.filter((i) => i.status === "FAIL").length;
  const warn = items.filter((i) => i.status === "WARN").length;
  const pct  = items.length > 0 ? Math.round((pass / items.length) * 100) : 0;

  return (
    <div className="border border-slate-700 rounded-lg overflow-hidden mb-3">
      {/* Accordion header */}
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-3 bg-slate-800 hover:bg-slate-700 cursor-pointer transition"
      >
        <div className="flex items-center gap-3">
          {open
            ? <ChevronDown className="w-4 h-4 text-slate-400" />
            : <ChevronRight className="w-4 h-4 text-slate-400" />
          }
          <span className="text-sm font-bold text-white">{domain}</span>
          <span className="text-xs text-slate-400">{items.length}개 항목</span>
          {fail > 0 && (
            <span className="px-2 py-0.5 bg-red-600 text-white text-xs rounded font-bold">
              FAIL {fail}
            </span>
          )}
          {warn > 0 && (
            <span className="px-2 py-0.5 bg-amber-600 text-white text-xs rounded font-bold">
              WARN {warn}
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          <div className="w-32 h-1.5 bg-slate-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-emerald-500 rounded-full transition-all"
              style={{ width: `${pct}%` }}
            />
          </div>
          <span className="text-xs text-slate-400 w-12 text-right">{pass}/{items.length}</span>
        </div>
      </button>

      {/* Items */}
      {open && (
        <div>
          {items.map((item) => (
            <ItemRow key={item.id} item={item} onUpdate={onUpdate} />
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// HighPrioritySection
// ---------------------------------------------------------------------------

interface HighPrioritySectionProps {
  items: ValidationItem[];
  onUpdate: (id: number, fields: Partial<Pick<ValidationItem, "status" | "note" | "assignee">>) => Promise<void>;
}

function HighPrioritySection({ items, onUpdate }: HighPrioritySectionProps) {
  const allPass = items.length > 0 && items.every((i) => i.status === "PASS");
  const failItems = items.filter((i) => i.status === "FAIL");
  const pendingItems = items.filter((i) => i.status === "PENDING");

  return (
    <div className="border-2 border-red-700 rounded-lg overflow-hidden mb-6">
      <div className="flex items-center justify-between px-4 py-3 bg-red-950/40">
        <div className="flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 text-red-400" />
          <span className="text-sm font-bold text-red-300">
            HIGH 우선순위 항목 ({items.length}개)
          </span>
          {failItems.length > 0 && (
            <span className="px-2 py-0.5 bg-red-600 text-white text-xs rounded">
              FAIL {failItems.length}
            </span>
          )}
          {pendingItems.length > 0 && (
            <span className="px-2 py-0.5 bg-slate-600 text-slate-300 text-xs rounded">
              미완료 {pendingItems.length}
            </span>
          )}
        </div>
        <span
          className={cn(
            "px-3 py-1 rounded text-xs font-bold",
            allPass ? "bg-emerald-600 text-white" : "bg-slate-700 text-slate-400"
          )}
        >
          {allPass ? "전체 PASS" : "진행 중"}
        </span>
      </div>
      <div>
        {items.map((item) => (
          <ItemRow key={item.id} item={item} onUpdate={onUpdate} />
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// StickyProgressBar
// ---------------------------------------------------------------------------

function StickyProgressBar({
  pass,
  total,
  startedAt,
}: {
  pass: number;
  total: number;
  startedAt: number | null;
}) {
  const pct = total > 0 ? Math.round((pass / total) * 100) : 0;

  // Estimate completion
  let etaLabel = "";
  if (startedAt !== null && pass > 0 && pass < total) {
    const elapsed = (Date.now() - startedAt) / 1000 / 60; // minutes
    const rate = pass / elapsed; // items per minute
    const remaining = total - pass;
    const etaMins = Math.ceil(remaining / rate);
    if (etaMins < 60) {
      etaLabel = ` — 예상 완료: 약 ${etaMins}분 후`;
    } else {
      etaLabel = ` — 예상 완료: 약 ${Math.ceil(etaMins / 60)}시간 후`;
    }
  }

  return (
    <div className="sticky bottom-0 bg-slate-900 border-t border-slate-700 px-6 py-3 z-20">
      <div className="flex items-center gap-4">
        <div className="flex-1 h-2 bg-slate-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-emerald-500 rounded-full transition-all duration-500"
            style={{ width: `${pct}%` }}
          />
        </div>
        <span className="text-sm text-slate-300 whitespace-nowrap">
          <span className="text-white font-bold">{pass}</span>
          <span className="text-slate-500"> / {total} 완료</span>
          <span className="text-slate-500"> ({pct}%)</span>
          {etaLabel && <span className="text-slate-500 text-xs">{etaLabel}</span>}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Validation page
// ---------------------------------------------------------------------------

const DOMAIN_ORDER = [
  "01_GG_Process",
  "02_Static_Schema",
  "03_Data_Validation",
  "04_Special_Objects",
  "05_Migration_Caution",
];

export default function Validation() {
  const [items, setItems] = useState<ValidationItem[]>([]);
  const [summary, setSummary] = useState<SummaryData | null>(null);
  const [loading, setLoading] = useState(true);
  const [startedAt] = useState<number | null>(Date.now());
  const domainRefs = useRef<Record<string, HTMLDivElement | null>>({});

  // Fetch all items
  const fetchItems = useCallback(async () => {
    try {
      const res = await api.get<ValidationItem[]>("/validation/items");
      setItems(res.data);
    } catch {
      // silently ignore
    }
  }, []);

  // Fetch summary
  const fetchSummary = useCallback(async () => {
    try {
      const res = await api.get<SummaryData>("/validation/summary");
      setSummary(res.data);
    } catch {
      // silently ignore
    }
  }, []);

  useEffect(() => {
    Promise.all([fetchItems(), fetchSummary()]).finally(() => setLoading(false));
  }, [fetchItems, fetchSummary]);

  // Optimistic update
  const handleUpdate = useCallback(
    async (id: number, fields: Partial<Pick<ValidationItem, "status" | "note" | "assignee">>) => {
      // Optimistic local update
      setItems((prev) =>
        prev.map((item) => (item.id === id ? { ...item, ...fields } : item))
      );

      try {
        await api.patch(`/validation/items/${id}`, fields);
        // Refresh summary
        await fetchSummary();
      } catch {
        // Rollback on failure
        await fetchItems();
      }
    },
    [fetchItems, fetchSummary]
  );

  // Group by domain
  const byDomain = DOMAIN_ORDER.reduce<Record<string, ValidationItem[]>>((acc, d) => {
    acc[d] = items.filter((i) => i.domain === d);
    return acc;
  }, {});

  const highItems = items.filter((i) => i.priority === "HIGH");

  const scrollToDomain = (domain: string) => {
    domainRefs.current[domain]?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64 text-slate-400">
        <span className="animate-pulse">검증 항목 로드 중...</span>
      </div>
    );
  }

  const goNogo = summary?.go_nogo ?? "PENDING";
  const passCount = summary?.pass_count ?? 0;
  const total = summary?.total ?? items.length;

  // Determine which domains have FAIL/WARN to default-open
  const domainsWithIssues = new Set(
    items
      .filter((i) => i.status === "FAIL" || i.status === "WARN")
      .map((i) => i.domain)
  );

  return (
    <div className="flex flex-col h-full bg-slate-900 overflow-hidden">
      <div className="flex-1 overflow-y-auto px-6 py-6">
        {/* ── Top: Go/No-Go + progress headline ── */}
        <div className="flex items-center gap-6 mb-8">
          <GoNoBadge goNogo={goNogo} size="lg" showLabel />
          <div>
            <div className="text-3xl font-bold text-white">
              {passCount}
              <span className="text-slate-500 text-xl font-normal">/{total} 완료</span>
            </div>
            <div className="text-sm text-slate-400 mt-0.5">Phase 6 — 검증 136항목</div>
          </div>
        </div>

        {/* ── Level 3: Domain progress cards ── */}
        {summary && (
          <div className="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-3 mb-8">
            {summary.domain_summary.map((ds) => (
              <DomainCard
                key={ds.domain}
                summary={ds}
                onClick={() => scrollToDomain(ds.domain)}
              />
            ))}
          </div>
        )}

        {/* ── Level 2: HIGH priority items ── */}
        {highItems.length > 0 && (
          <HighPrioritySection items={highItems} onUpdate={handleUpdate} />
        )}

        {/* ── Level 4: Domain accordions ── */}
        <div>
          {DOMAIN_ORDER.map((domain) => {
            const domainItems = byDomain[domain] ?? [];
            if (domainItems.length === 0) return null;
            const hasIssues = domainsWithIssues.has(domain);

            return (
              <div
                key={domain}
                ref={(el) => { domainRefs.current[domain] = el; }}
              >
                <DomainAccordion
                  domain={domain}
                  items={domainItems}
                  defaultOpen={hasIssues}
                  onUpdate={handleUpdate}
                />
              </div>
            );
          })}
        </div>
      </div>

      {/* ── Sticky bottom progress bar ── */}
      <StickyProgressBar pass={passCount} total={total} startedAt={startedAt} />
    </div>
  );
}
