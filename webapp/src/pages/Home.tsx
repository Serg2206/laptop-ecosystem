import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import FadeIn from '../components/FadeIn';

const features = [
  {
    icon: '📝',
    title: 'Word Template',
    description: 'Academic-Modern.dotx with 10 pre-configured styles for professional documents.',
    link: '/templates',
    color: 'from-blue-500 to-blue-700',
  },
  {
    icon: '🎨',
    title: 'PowerPoint Template',
    description: 'Conference-Pro.potx with 8 slide layouts for academic presentations.',
    link: '/templates',
    color: 'from-purple-500 to-purple-700',
  },
  {
    icon: '🔤',
    title: '9 Font Families',
    description: 'Inter, Montserrat, Merriweather, Crimson Text, Playfair Display, Source Code Pro.',
    link: '/fonts',
    color: 'from-pink-500 to-pink-700',
  },
];

const stats = [
  { value: '9', label: 'Font Families' },
  { value: '10', label: 'Word Styles' },
  { value: '8', label: 'Slide Layouts' },
  { value: '5', label: 'PowerShell Scripts' },
];

const installCode = `# One-click installer
iwr -useb https://raw.githubusercontent.com/Serg2206/laptop-ecosystem/main/Setup-Everything.ps1 | iex`;

export default function Home() {
  return (
    <div>
      {/* Hero Section */}
      <section className="relative overflow-hidden bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 text-white py-20 sm:py-28">
        <div className="absolute inset-0 bg-[url('data:image/svg+xml,%3Csvg width=\"60\" height=\"60\" viewBox=\"0 0 60 60\" xmlns=\"http://www.w3.org/2000/svg\"%3E%3Cg fill=\"none\" fill-rule=\"evenodd\"%3E%3Cg fill=\"%234f46e5\" fill-opacity=\"0.05\"%3E%3Cpath d=\"M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z\"/%3E%3C/g%3E%3C/g%3E%3C/svg%3E')] opacity-20" />
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="text-center"
          >
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold mb-6 leading-tight">
              <span className="bg-gradient-to-r from-blue-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
                MS 365 Design System
              </span>
            </h1>
            <p className="text-lg sm:text-xl text-slate-300 max-w-3xl mx-auto mb-10">
              Professional fonts, templates, and automation tools for academic publishing.
              Integrated with Obsidian, Notion, and GitHub.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Link
                to="/templates"
                className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl shadow-lg hover:shadow-xl transition-all duration-200"
              >
                Browse Templates
              </Link>
              <Link
                to="/dashboard"
                className="px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-semibold rounded-xl backdrop-blur-sm transition-all duration-200"
              >
                View Dashboard
              </Link>
            </div>
          </motion.div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-12 bg-white border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            {stats.map((stat, i) => (
              <FadeIn key={stat.label} delay={i * 0.1} className="text-center">
                <div className="text-3xl sm:text-4xl font-bold text-slate-900">{stat.value}</div>
                <div className="text-sm text-slate-500 mt-1">{stat.label}</div>
              </FadeIn>
            ))}
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-16 sm:py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <FadeIn className="text-center mb-12">
            <h2 className="text-3xl font-bold text-slate-900">What&apos;s Included</h2>
            <p className="text-slate-500 mt-2">Everything you need for professional academic publishing</p>
          </FadeIn>

          <div className="grid md:grid-cols-3 gap-8">
            {features.map((feature, i) => (
              <FadeIn key={feature.title} delay={i * 0.15}>
                <Link
                  to={feature.link}
                  className="block group bg-white rounded-2xl shadow-sm hover:shadow-lg border border-slate-200 p-8 transition-all duration-300 hover:-translate-y-1"
                >
                  <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${feature.color} flex items-center justify-center text-2xl mb-4 shadow-md group-hover:scale-110 transition-transform`}>
                    {feature.icon}
                  </div>
                  <h3 className="text-xl font-semibold text-slate-900 mb-2 group-hover:text-blue-600 transition-colors">
                    {feature.title}
                  </h3>
                  <p className="text-slate-500 text-sm leading-relaxed">{feature.description}</p>
                </Link>
              </FadeIn>
            ))}
          </div>
        </div>
      </section>

      {/* Quick Install Section */}
      <section className="py-16 bg-slate-900 text-white">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <FadeIn className="text-center mb-8">
            <h2 className="text-3xl font-bold mb-2">Quick Install</h2>
            <p className="text-slate-400">Run this command in PowerShell to set up everything</p>
          </FadeIn>

          <FadeIn delay={0.1}>
            <div className="bg-slate-800 rounded-xl p-4 sm:p-6 overflow-x-auto border border-slate-700">
              <pre className="text-sm text-green-400">
                <code>{installCode}</code>
              </pre>
            </div>
            <p className="text-center text-sm text-slate-500 mt-4">
              Requires PowerShell 5.1+ and administrative privileges
            </p>
          </FadeIn>
        </div>
      </section>
    </div>
  );
}
