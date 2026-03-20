import { cn } from "../lib/utils";
import type { GoNogo } from "../types";

interface GoNoBadgeProps {
  goNogo: GoNogo;
  size?: "sm" | "lg";
  showLabel?: boolean;
}

const LABEL: Record<GoNogo, string> = {
  GO:             "GO",
  CONDITIONAL_GO: "CONDITIONAL GO",
  NO_GO:          "NO-GO",
  PENDING:        "PENDING",
};

const BASE_STYLE: Record<GoNogo, string> = {
  GO:             "bg-emerald-600 text-white border-emerald-500",
  CONDITIONAL_GO: "bg-amber-500 text-black border-amber-400",
  NO_GO:          "bg-red-600 text-white border-red-500 animate-pulse",
  PENDING:        "bg-slate-600 text-slate-300 border-slate-500",
};

export default function GoNoBadge({
  goNogo,
  size = "sm",
  showLabel = true,
}: GoNoBadgeProps) {
  const isLg = size === "lg";

  return (
    <span
      className={cn(
        "inline-flex items-center justify-center font-bold tracking-widest rounded border",
        BASE_STYLE[goNogo],
        isLg
          ? "px-5 py-2 text-xl border-2"
          : "px-3 py-1 text-xs"
      )}
    >
      {showLabel && LABEL[goNogo]}
    </span>
  );
}
