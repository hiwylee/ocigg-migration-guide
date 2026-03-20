export default function Placeholder({ title }: { title: string }) {
  return (
    <div className="flex flex-col items-center justify-center h-full text-center select-none">
      <div className="text-5xl mb-4 opacity-30">🚧</div>
      <h2 className="text-xl font-bold text-white mb-1">{title}</h2>
      <p className="text-slate-500 text-sm">구현 예정 (Phase 3+)</p>
    </div>
  );
}
