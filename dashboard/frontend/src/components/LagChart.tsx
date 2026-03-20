import { useMemo } from "react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  ReferenceArea,
  Legend,
} from "recharts";
import { format, parseISO } from "date-fns";

export interface LagPoint {
  recorded_at: string;
  lag_seconds: number;
  process_name: string;
}

interface Props {
  data: LagPoint[];
  threshold: number;
  stableSince: string | null;
  loading?: boolean;
}

interface TooltipPayloadEntry {
  color?: string;
  name?: string;
  value?: number;
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: TooltipPayloadEntry[];
  label?: string;
}

function CustomTooltip({ active, payload, label }: CustomTooltipProps) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-slate-900 border border-slate-700 rounded px-3 py-2 text-xs shadow-xl">
      <p className="text-slate-400 mb-1">{label}</p>
      {payload.map((entry, idx) => (
        <p key={idx} style={{ color: entry.color ?? "#94a3b8" }}>
          {entry.name}: {entry.value != null ? `${entry.value.toFixed(2)}s` : "—"}
        </p>
      ))}
    </div>
  );
}

export default function LagChart({ data, threshold, stableSince, loading }: Props) {
  // 임계 초과 구간 계산 (ReferenceArea 빨간 음영)
  const violationAreas = useMemo(() => {
    if (!data.length) return [];
    const areas: Array<{ x1: string; x2: string }> = [];
    let inViolation = false;
    let start = "";

    for (let i = 0; i < data.length; i++) {
      const pt = data[i];
      const over = pt.lag_seconds > threshold;
      if (over && !inViolation) {
        inViolation = true;
        start = pt.recorded_at;
      } else if (!over && inViolation) {
        inViolation = false;
        areas.push({ x1: start, x2: data[i - 1].recorded_at });
      }
    }
    if (inViolation && start) {
      areas.push({ x1: start, x2: data[data.length - 1].recorded_at });
    }
    return areas;
  }, [data, threshold]);

  // stableSince 마커 포맷
  const stableSinceLabel = useMemo(() => {
    if (!stableSince) return null;
    try {
      return format(parseISO(stableSince), "HH:mm");
    } catch {
      return null;
    }
  }, [stableSince]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-56 bg-slate-800 rounded-lg border border-slate-700">
        <span className="text-slate-500 text-sm animate-pulse">LAG 데이터 로딩 중...</span>
      </div>
    );
  }

  if (!data.length) {
    return (
      <div className="flex items-center justify-center h-56 bg-slate-800 rounded-lg border border-slate-700">
        <span className="text-slate-600 text-sm">LAG 이력 데이터가 없습니다</span>
      </div>
    );
  }

  return (
    <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
      <ResponsiveContainer width="100%" height={220}>
        <LineChart data={data} margin={{ top: 8, right: 16, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
          <XAxis
            dataKey="recorded_at"
            tickFormatter={(v: string) => {
              try {
                return format(parseISO(v), "HH:mm");
              } catch {
                return v;
              }
            }}
            tick={{ fill: "#94a3b8", fontSize: 11 }}
            tickLine={false}
            axisLine={{ stroke: "#475569" }}
            minTickGap={40}
          />
          <YAxis
            tick={{ fill: "#94a3b8", fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(v: number) => `${v}s`}
            width={42}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend
            wrapperStyle={{ fontSize: 11, color: "#94a3b8", paddingTop: 4 }}
          />

          {/* 임계 초과 구간 빨간 음영 */}
          {violationAreas.map((area, idx) => (
            <ReferenceArea
              key={idx}
              x1={area.x1}
              x2={area.x2}
              fill="#ef4444"
              fillOpacity={0.12}
            />
          ))}

          {/* 임계선 빨간 점선 */}
          <ReferenceLine
            y={threshold}
            stroke="#ef4444"
            strokeDasharray="4 3"
            strokeWidth={1.5}
            label={{
              value: `임계 ${threshold}s`,
              position: "insideTopRight",
              fill: "#ef4444",
              fontSize: 10,
            }}
          />

          {/* 24h 안정화 기산점 마커 */}
          {stableSince && stableSinceLabel && (
            <ReferenceLine
              x={stableSince}
              stroke="#34d399"
              strokeDasharray="3 3"
              strokeWidth={1.5}
              label={{
                value: `안정화 기산 ${stableSinceLabel}`,
                position: "insideTopLeft",
                fill: "#34d399",
                fontSize: 10,
              }}
            />
          )}

          <Line
            type="monotone"
            dataKey="lag_seconds"
            name="LAG (초)"
            stroke="#38bdf8"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4, fill: "#38bdf8" }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
