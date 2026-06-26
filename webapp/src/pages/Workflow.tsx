import FadeIn from '../components/FadeIn';

const tools = [
  { name: 'Obsidian', icon: '📝', color: 'bg-purple-100 text-purple-700 border-purple-200', description: 'Daily notes, research, drafts' },
  { name: 'Notion', icon: '🔮', color: 'bg-gray-100 text-gray-700 border-gray-200', description: 'Project management, databases' },
  { name: 'MS 365', icon: '📦', color: 'bg-blue-100 text-blue-700 border-blue-200', description: 'Word, PowerPoint, final docs' },
  { name: 'GitHub', icon: '🐙', color: 'bg-slate-100 text-slate-700 border-slate-200', description: 'Version control, backups' },
  { name: 'OneDrive', icon: '☁️', color: 'bg-sky-100 text-sky-700 border-sky-200', description: 'Cloud sync, file sharing' },
];

const connections = [
  { from: 'Obsidian', to: 'GitHub', label: 'Backup notes' },
  { from: 'Obsidian', to: 'Notion', label: 'Sync pages' },
  { from: 'Notion', to: 'MS 365', label: 'Export reports' },
  { from: 'MS 365', to: 'OneDrive', label: 'Auto-save' },
  { from: 'GitHub', to: 'OneDrive', label: 'Mirror repo' },
];

const schedule = [
  { time: '07:00', task: 'Daily Notes auto-created in Obsidian', tool: 'Obsidian' },
  { time: '08:00', task: 'OneDrive sync check on login', tool: 'OneDrive' },
  { time: '10:00', task: 'Research writing in Obsidian → Notion sync', tool: 'Obsidian + Notion' },
  { time: '14:00', task: 'Format document in Word with Academic-Modern template', tool: 'MS 365' },
  { time: '16:00', task: 'Create presentation with Conference-Pro template', tool: 'MS 365' },
  { time: '18:00', task: 'GitHub auto-backup + OneDrive mirror sync', tool: 'GitHub + OneDrive' },
];

export default function Workflow() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <FadeIn>
        <div className="text-center mb-10">
          <h1 className="text-3xl sm:text-4xl font-bold text-slate-900">Workflow</h1>
          <p className="text-slate-500 mt-2">How your tools connect and work together</p>
        </div>
      </FadeIn>

      {/* Data Flow Diagram */}
      <FadeIn delay={0.1}>
        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 sm:p-8 mb-10">
          <h2 className="text-lg font-semibold text-slate-900 mb-6">🔗 Data Flow</h2>

          {/* Tools grid */}
          <div className="flex flex-wrap justify-center gap-4 mb-6">
            {tools.map((tool) => (
              <div
                key={tool.name}
                className={`flex items-center gap-2 px-4 py-3 rounded-xl border ${tool.color} font-medium`}
              >
                <span className="text-xl">{tool.icon}</span>
                <span>{tool.name}</span>
              </div>
            ))}
          </div>

          {/* Connections */}
          <div className="space-y-2 max-w-xl mx-auto">
            {connections.map((conn) => (
              <div key={`${conn.from}-${conn.to}`} className="flex items-center gap-3 text-sm">
                <span className="font-medium text-slate-700 w-20 text-right">{conn.from}</span>
                <div className="flex-1 flex items-center gap-2">
                  <div className="flex-1 h-px bg-gradient-to-r from-slate-300 to-slate-300" />
                  <span className="px-2 py-0.5 bg-slate-100 text-slate-600 text-xs rounded whitespace-nowrap">
                    {conn.label}
                  </span>
                  <div className="flex-1 h-px bg-slate-300" />
                </div>
                <span className="font-medium text-slate-700 w-20">{conn.to}</span>
              </div>
            ))}
          </div>
        </div>
      </FadeIn>

      {/* Daily Schedule */}
      <FadeIn delay={0.2}>
        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
          <div className="p-6 border-b border-slate-200">
            <h2 className="text-lg font-semibold text-slate-900">📅 Daily Schedule</h2>
            <p className="text-sm text-slate-500 mt-1">Automated workflow throughout the day</p>
          </div>
          <div className="divide-y divide-slate-100">
            {schedule.map((item, i) => (
              <div key={i} className="flex items-start gap-4 p-4 hover:bg-slate-50 transition-colors">
                <div className="w-14 flex-shrink-0">
                  <span className="inline-block px-2 py-1 bg-blue-50 text-blue-700 text-xs font-mono font-medium rounded">
                    {item.time}
                  </span>
                </div>
                <div className="flex-1">
                  <div className="text-sm text-slate-800">{item.task}</div>
                </div>
                <div className="flex-shrink-0">
                  <span className="px-2 py-1 bg-slate-100 text-slate-600 text-xs rounded">
                    {item.tool}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </FadeIn>
    </div>
  );
}
