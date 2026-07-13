import { useState, useCallback, useMemo } from 'react';
import FadeIn from '../components/FadeIn';

// Структура JSON-отчёта Test-LaptopHealth.ps1
interface HealthReport {
  GeneratedAt: string;
  Computer: string;
  HealthScore: number;
  Errors: number;
  Warnings: number;
  Sections: Record<string, Record<string, unknown>>;
}

const sectionMeta: Record<string, { icon: string; title: string }> = {
  System: { icon: '💻', title: 'Система' },
  CPU: { icon: '⚙️', title: 'Процессор' },
  Memory: { icon: '🧠', title: 'Память' },
  Disks: { icon: '💾', title: 'Диски' },
  Battery: { icon: '🔋', title: 'Батарея' },
  GPU: { icon: '🖥️', title: 'Видео' },
  Network: { icon: '🌐', title: 'Сеть' },
  Devices: { icon: '🔌', title: 'Устройства' },
  Security: { icon: '🛡️', title: 'Безопасность' },
  Stability: { icon: '📈', title: 'Стабильность' },
};

function scoreTone(score: number) {
  if (score >= 85) return { text: 'text-green-600', stroke: '#16a34a', label: 'Отличное состояние' };
  if (score >= 60) return { text: 'text-yellow-600', stroke: '#ca8a04', label: 'Есть замечания' };
  return { text: 'text-red-600', stroke: '#dc2626', label: 'Требуется внимание' };
}

function fmtValue(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'boolean') return v ? 'да' : 'нет';
  if (Array.isArray(v)) return `${v.length} элем.`;
  if (typeof v === 'object') return Object.entries(v as object).map(([k, x]) => `${k}: ${x}`).join(', ');
  return String(v);
}

// Кольцевой индикатор Health Score
function ScoreRing({ score }: { score: number }) {
  const tone = scoreTone(score);
  const r = 52;
  const c = 2 * Math.PI * r;
  return (
    <svg width="140" height="140" viewBox="0 0 140 140" role="img" aria-label={`Health Score ${score} из 100`}>
      <circle cx="70" cy="70" r={r} fill="none" stroke="#e2e8f0" strokeWidth="10" />
      <circle
        cx="70" cy="70" r={r} fill="none"
        stroke={tone.stroke} strokeWidth="10" strokeLinecap="round"
        strokeDasharray={c} strokeDashoffset={c * (1 - score / 100)}
        transform="rotate(-90 70 70)"
        className="transition-all duration-700"
      />
      <text x="70" y="66" textAnchor="middle" className="fill-slate-900" fontSize="30" fontWeight="700">{score}</text>
      <text x="70" y="88" textAnchor="middle" className="fill-slate-400" fontSize="12">из 100</text>
    </svg>
  );
}

// Тренд Health Score по загруженным отчётам (одна серия — легенда не нужна)
function TrendChart({ reports }: { reports: HealthReport[] }) {
  const [hover, setHover] = useState<number | null>(null);
  const W = 640, H = 180, PAD = { l: 34, r: 14, t: 14, b: 26 };
  const pts = reports.map((rep, i) => ({
    x: PAD.l + (reports.length === 1 ? 0 : (i * (W - PAD.l - PAD.r)) / (reports.length - 1)),
    y: PAD.t + ((100 - rep.HealthScore) * (H - PAD.t - PAD.b)) / 100,
    rep,
  }));
  const line = pts.map((p) => `${p.x},${p.y}`).join(' ');
  return (
    <div className="overflow-x-auto">
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full min-w-[480px]" role="img" aria-label="Тренд Health Score по отчётам">
        {[0, 50, 100].map((v) => {
          const y = PAD.t + ((100 - v) * (H - PAD.t - PAD.b)) / 100;
          return (
            <g key={v}>
              <line x1={PAD.l} y1={y} x2={W - PAD.r} y2={y} stroke="#e2e8f0" strokeWidth="1" />
              <text x={PAD.l - 6} y={y + 4} textAnchor="end" fontSize="10" className="fill-slate-400">{v}</text>
            </g>
          );
        })}
        <polyline points={line} fill="none" stroke="#2a78d6" strokeWidth="2" strokeLinejoin="round" />
        {pts.map((p, i) => (
          <g key={i}>
            <circle cx={p.x} cy={p.y} r={hover === i ? 6 : 4} fill="#2a78d6" stroke="#ffffff" strokeWidth="2" />
            {/* Увеличенная зона наведения */}
            <circle
              cx={p.x} cy={p.y} r="14" fill="transparent"
              onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}
            />
            {hover === i && (
              <g pointerEvents="none">
                <rect x={Math.min(p.x + 8, W - 186)} y={Math.max(p.y - 40, 2)} width="178" height="34" rx="6" fill="#0f172a" opacity="0.92" />
                <text x={Math.min(p.x + 15, W - 179)} y={Math.max(p.y - 25, 17)} fontSize="11" fill="#ffffff" fontWeight="600">
                  Score {p.rep.HealthScore} · {p.rep.Errors} ош. · {p.rep.Warnings} пред.
                </text>
                <text x={Math.min(p.x + 15, W - 179)} y={Math.max(p.y - 12, 30)} fontSize="10" fill="#cbd5e1">
                  {p.rep.GeneratedAt}
                </text>
              </g>
            )}
          </g>
        ))}
        {pts.map((p, i) => (
          (i === 0 || i === pts.length - 1) && (
            <text key={`d${i}`} x={p.x} y={H - 8} textAnchor={i === 0 ? 'start' : 'end'} fontSize="10" className="fill-slate-400">
              {p.rep.GeneratedAt.slice(0, 10)}
            </text>
          )
        ))}
      </svg>
    </div>
  );
}

export default function Health() {
  const [reports, setReports] = useState<HealthReport[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [openSection, setOpenSection] = useState<string | null>(null);

  const addFiles = useCallback(async (files: FileList | File[]) => {
    setError(null);
    const parsed: HealthReport[] = [];
    for (const f of Array.from(files)) {
      try {
        const data = JSON.parse(await f.text());
        if (typeof data.HealthScore !== 'number' || !data.Sections) {
          throw new Error('не похоже на отчёт Test-LaptopHealth');
        }
        parsed.push(data as HealthReport);
      } catch (e) {
        setError(`${f.name}: ${e instanceof Error ? e.message : 'не удалось прочитать'}`);
      }
    }
    if (parsed.length) {
      setReports((prev) => {
        const merged = [...prev, ...parsed];
        // Дедупликация по времени генерации + сортировка по дате
        const unique = Array.from(new Map(merged.map((r) => [r.GeneratedAt, r])).values());
        return unique.sort((a, b) => a.GeneratedAt.localeCompare(b.GeneratedAt));
      });
    }
  }, []);

  const latest = reports.length ? reports[reports.length - 1] : null;
  const tone = latest ? scoreTone(latest.HealthScore) : null;

  // Ключевые метрики из последнего отчёта (все поля опциональны — отчёт мог быть неполным)
  const kpis = useMemo(() => {
    if (!latest) return [];
    const s = latest.Sections;
    const num = (sec: string, key: string): number | undefined => {
      const v = s[sec]?.[key];
      return typeof v === 'number' ? v : undefined;
    };
    const items: { label: string; value: string; icon: string }[] = [];
    const cpu = num('CPU', 'LoadPercent');
    if (cpu !== undefined) items.push({ icon: '⚙️', label: 'Загрузка CPU', value: `${cpu}%` });
    const ram = num('Memory', 'UsedPercent');
    if (ram !== undefined) items.push({ icon: '🧠', label: 'Память занята', value: `${ram}%` });
    const vols = s.Disks?.Volumes;
    if (Array.isArray(vols) && vols.length) {
      const minFree = Math.min(...vols.map((v: { FreePercent?: number }) => v.FreePercent ?? 100));
      items.push({ icon: '💾', label: 'Мин. свободно на диске', value: `${minFree}%` });
    }
    const wear = num('Battery', 'WearPercent');
    if (wear !== undefined) items.push({ icon: '🔋', label: 'Износ батареи', value: `${wear}%` });
    const lat = num('Network', 'AvgLatencyMs');
    if (lat !== undefined) items.push({ icon: '🌐', label: 'Задержка сети', value: `${lat} ms` });
    const up = num('System', 'UptimeDays');
    if (up !== undefined) items.push({ icon: '⏱️', label: 'Uptime', value: `${up} дн.` });
    return items;
  }, [latest]);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <FadeIn>
        <h1 className="text-3xl sm:text-4xl font-bold text-slate-900">Laptop Health</h1>
        <p className="text-slate-500 mt-1 mb-8">
          Отчёты диагностики <code className="text-xs bg-slate-100 px-1.5 py-0.5 rounded">Test-LaptopHealth.ps1</code> — перетащите JSON-файлы из папки отчётов
        </p>
      </FadeIn>

      {/* Зона загрузки */}
      <FadeIn>
        <label
          onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => { e.preventDefault(); setDragOver(false); addFiles(e.dataTransfer.files); }}
          className={`block cursor-pointer rounded-2xl border-2 border-dashed p-8 text-center transition-colors mb-8 ${
            dragOver ? 'border-blue-400 bg-blue-50' : 'border-slate-300 bg-white hover:border-blue-300'
          }`}
        >
          <input
            type="file" accept=".json" multiple className="hidden"
            onChange={(e) => e.target.files && addFiles(e.target.files)}
          />
          <div className="text-3xl mb-2">📥</div>
          <div className="font-medium text-slate-700">
            Перетащите файлы <span className="font-mono text-sm">laptop-health-*.json</span> или нажмите для выбора
          </div>
          <div className="text-sm text-slate-400 mt-1">
            OneDrive\LaptopHealth (автодиагностика) или laptop-ecosystem\reports
          </div>
          {reports.length > 0 && (
            <div className="text-sm text-blue-600 mt-2 font-medium">Загружено отчётов: {reports.length}</div>
          )}
        </label>
      </FadeIn>

      {error && (
        <div className="mb-8 p-4 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700">⚠️ {error}</div>
      )}

      {!latest && (
        <FadeIn>
          <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-8">
            <h2 className="text-lg font-semibold text-slate-900 mb-3">Как получить отчёты</h2>
            <ol className="list-decimal list-inside space-y-2 text-sm text-slate-600">
              <li>Разовая диагностика: <code className="bg-slate-100 px-1.5 py-0.5 rounded">.\scripts\Test-LaptopHealth.ps1 -Full -Export</code></li>
              <li>Или еженедельная автодиагностика: <code className="bg-slate-100 px-1.5 py-0.5 rounded">.\scripts\Register-HealthCheckTask.ps1 -RunNow</code></li>
              <li>Загрузите сюда несколько JSON-отчётов — увидите тренд состояния ноутбука во времени.</li>
            </ol>
          </div>
        </FadeIn>
      )}

      {latest && tone && (
        <>
          {/* Итог последнего отчёта */}
          <div className="grid lg:grid-cols-3 gap-6 mb-8">
            <FadeIn>
              <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 flex items-center gap-6">
                <ScoreRing score={latest.HealthScore} />
                <div>
                  <div className={`text-lg font-semibold ${tone.text}`}>{tone.label}</div>
                  <div className="text-sm text-slate-500 mt-1">{latest.Computer} · {latest.GeneratedAt}</div>
                  <div className="text-sm text-slate-600 mt-2">
                    Ошибок: <span className="font-semibold text-red-600">{latest.Errors}</span> ·
                    Предупреждений: <span className="font-semibold text-yellow-600"> {latest.Warnings}</span>
                  </div>
                </div>
              </div>
            </FadeIn>

            {/* KPI-плитки */}
            <FadeIn delay={0.1}>
              <div className="lg:col-span-2 grid grid-cols-2 sm:grid-cols-3 gap-3 h-full">
                {kpis.map((k) => (
                  <div key={k.label} className="bg-white rounded-xl shadow-sm border border-slate-200 p-4 flex flex-col justify-center">
                    <div className="text-xs text-slate-500 flex items-center gap-1.5"><span>{k.icon}</span>{k.label}</div>
                    <div className="text-2xl font-bold text-slate-900 mt-1">{k.value}</div>
                  </div>
                ))}
              </div>
            </FadeIn>
          </div>

          {/* Тренд */}
          {reports.length >= 2 && (
            <FadeIn>
              <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 mb-8">
                <h2 className="text-lg font-semibold text-slate-900 mb-4">Тренд Health Score ({reports.length} отчётов)</h2>
                <TrendChart reports={reports} />
              </div>
            </FadeIn>
          )}

          {/* Детали по секциям */}
          <FadeIn>
            <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6">
              <h2 className="text-lg font-semibold text-slate-900 mb-4">Детали последнего отчёта</h2>
              <div className="grid sm:grid-cols-2 gap-3">
                {Object.entries(latest.Sections).map(([name, data]) => {
                  const meta = sectionMeta[name] ?? { icon: '📄', title: name };
                  const isOpen = openSection === name;
                  return (
                    <div key={name} className="border border-slate-200 rounded-xl overflow-hidden">
                      <button
                        onClick={() => setOpenSection(isOpen ? null : name)}
                        className="w-full flex items-center justify-between p-3 bg-slate-50 hover:bg-slate-100 transition-colors text-left"
                      >
                        <span className="font-medium text-slate-800 text-sm">{meta.icon} {meta.title}</span>
                        <span className="text-slate-400 text-xs">{isOpen ? '▲' : '▼'}</span>
                      </button>
                      {isOpen && (
                        <table className="w-full text-xs">
                          <tbody>
                            {Object.entries(data).map(([k, v]) => (
                              <tr key={k} className="border-t border-slate-100">
                                <td className="px-3 py-1.5 text-slate-500 w-2/5">{k}</td>
                                <td className="px-3 py-1.5 text-slate-800 break-words">{fmtValue(v)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          </FadeIn>
        </>
      )}
    </div>
  );
}
