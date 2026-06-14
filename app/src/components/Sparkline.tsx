import { sparkPath, flagFor, FLAG_HSL, type Measurement } from "@/lib/health";

export function Sparkline({
  rows,
  w = 160,
  h = 34,
  colorByFlag = true,
}: {
  rows: Measurement[];
  w?: number;
  h?: number;
  colorByFlag?: boolean;
}) {
  const sp = sparkPath(rows, w, h);
  if (!sp) return <svg width={w} height={h} className="block" />;
  const lc = colorByFlag ? FLAG_HSL[flagFor(sp.last) || ""] || "hsl(var(--muted-foreground))" : "hsl(var(--muted-foreground))";
  return (
    <svg width={w} height={h} className="block overflow-visible">
      <defs>
        <linearGradient id="sparkfade" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="hsl(var(--muted-foreground))" stopOpacity="0.25" />
          <stop offset="100%" stopColor="hsl(var(--muted-foreground))" stopOpacity="0.75" />
        </linearGradient>
      </defs>
      <path d={sp.d} fill="none" stroke="url(#sparkfade)" strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={sp.cx} cy={sp.cy} r={2.6} fill={lc} />
    </svg>
  );
}
