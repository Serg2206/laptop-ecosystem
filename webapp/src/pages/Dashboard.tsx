import { useState, useEffect } from 'react';
import FadeIn from '../components/FadeIn';

interface ServiceStatus {
  name: string;
  icon: string;
  status: 'connected' | 'disconnected' | 'warning';
  description: string;
}

const services: ServiceStatus[] = [
  { name: 'OneDrive', icon: '☁️', status: 'connected', description: 'Cloud sync active' },
  { name: 'Obsidian Vault', icon: '📝', status: 'connected', description: 'Vault accessible' },
  { name: 'Notion API', icon: '🔮', status: 'warning', description: 'Token required' },
  { name: 'GitHub', icon: '🐙', status: 'connected', description: 'Repo synced' },
];

const tasks = [
  { name: 'Daily Notes', schedule: '07:00 daily', status: 'Enabled' },
  { name: 'OneDrive AutoStart', schedule: 'On logon', status: 'Enabled' },
  { name: 'GitHub Backup', schedule: '18:00 daily', status: 'Enabled' },
];

const activities = [
  { time: '07:00', action: 'Daily Notes created', icon: '📝' },
  { time: '08:30', action: 'OneDrive sync started', icon: '☁️' },
  { time: '10:15', action: 'Template files updated', icon: '🎨' },
  { time: '14:00', action: 'GitHub backup completed', icon: '✅' },
  { time: '18:00', action: 'Scheduled backup running', icon: '🔄' },
];

export default function Dashboard() {
  const [currentTime, setCurrentTime] = useState(new Date());

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const statusColors = {
    connected: 'bg-green-100 text-green-700 border-green-200',
    disconnected: 'bg-red-100 text-red-700 border-red-200',
    warning: 'bg-yellow-100 text-yellow-700 border-yellow-200',
  };

  const statusLabels = {
    connected: 'Connected',
    disconnected: 'Disconnected',
    warning: 'Needs Setup',
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <FadeIn>
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-10">
          <div>
            <h1 className="text-3xl sm:text-4xl font-bold text-slate-900">Workspace Dashboard</h1>
            <p className="text-slate-500 mt-1">Real-time status of your laptop ecosystem</p>
          </div>
          <div className="text-right">
            <div className="text-2xl font-mono font-bold text-slate-800">
              {currentTime.toLocaleTimeString('ru-RU')}
            </div>
            <div className="text-sm text-slate-500">
              {currentTime.toLocaleDateString('ru-RU', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
            </div>
          </div>
        </div>
      </FadeIn>

      {/* Service cards */}
      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-10">
        {services.map((service, i) => (
          <FadeIn key={service.name} delay={i * 0.1}>
            <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-5">
              <div className="flex items-center justify-between mb-3">
                <span className="text-2xl">{service.icon}</span>
                <span className={`px-2.5 py-1 text-xs font-medium rounded-full border ${statusColors[service.status]}`}>
                  {statusLabels[service.status]}
                </span>
              </div>
              <h3 className="font-semibold text-slate-900">{service.name}</h3>
              <p className="text-xs text-slate-500 mt-1">{service.description}</p>
            </div>
          </FadeIn>
        ))}
      </div>

      <div className="grid lg:grid-cols-2 gap-8">
        {/* Task Scheduler */}
        <FadeIn>
          <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-900 mb-4">⏰ Scheduled Tasks</h2>
            <div className="space-y-3">
              {tasks.map((task) => (
                <div key={task.name} className="flex items-center justify-between p-3 bg-slate-50 rounded-lg">
                  <div>
                    <div className="font-medium text-slate-900 text-sm">{task.name}</div>
                    <div className="text-xs text-slate-500">{task.schedule}</div>
                  </div>
                  <span className="px-2.5 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full">
                    {task.status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </FadeIn>

        {/* Activity Timeline */}
        <FadeIn delay={0.1}>
          <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-900 mb-4">📋 Recent Activity</h2>
            <div className="space-y-0">
              {activities.map((activity, i) => (
                <div key={i} className="flex items-start gap-3 pb-4 relative">
                  {i < activities.length - 1 && (
                    <div className="absolute left-[15px] top-8 bottom-0 w-px bg-slate-200" />
                  )}
                  <div className="w-8 h-8 bg-blue-50 rounded-full flex items-center justify-center text-sm flex-shrink-0">
                    {activity.icon}
                  </div>
                  <div>
                    <div className="text-sm text-slate-700">{activity.action}</div>
                    <div className="text-xs text-slate-400">{activity.time}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </FadeIn>
      </div>

      {/* Progress section */}
      <FadeIn delay={0.2}>
        <div className="mt-8 bg-white rounded-2xl shadow-sm border border-slate-200 p-6">
          <h2 className="text-lg font-semibold text-slate-900 mb-4">📊 System Health</h2>
          <div className="space-y-4">
            {[
              { label: 'OneDrive Sync', value: 92, color: 'bg-blue-500' },
              { label: 'GitHub Backup', value: 100, color: 'bg-green-500' },
              { label: 'Vault Sync', value: 78, color: 'bg-purple-500' },
              { label: 'Notion Integration', value: 45, color: 'bg-yellow-500' },
            ].map((item) => (
              <div key={item.label}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-slate-700">{item.label}</span>
                  <span className="text-slate-500">{item.value}%</span>
                </div>
                <div className="w-full bg-slate-100 rounded-full h-2.5">
                  <div
                    className={`${item.color} h-2.5 rounded-full transition-all duration-500`}
                    style={{ width: `${item.value}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      </FadeIn>
    </div>
  );
}
