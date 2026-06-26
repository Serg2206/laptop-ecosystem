import { useState } from 'react';
import FadeIn from '../components/FadeIn';

const wordStyles = [
  { name: 'Title', font: 'Montserrat', size: '28pt', usage: 'Document title' },
  { name: 'Heading 1', font: 'Montserrat', size: '20pt', usage: 'Major sections' },
  { name: 'Heading 2', font: 'Montserrat', size: '16pt', usage: 'Subsections' },
  { name: 'Heading 3', font: 'Montserrat', size: '13pt', usage: 'Sub-subsections' },
  { name: 'Heading 4', font: 'Montserrat', size: '11pt', usage: 'Minor headings' },
  { name: 'Normal', font: 'Merriweather', size: '11pt', usage: 'Body text' },
  { name: 'Quote', font: 'Crimson Text', size: '11pt', usage: 'Block quotations' },
  { name: 'Caption', font: 'Inter', size: '10pt', usage: 'Figure/table captions' },
  { name: 'Reference', font: 'Inter', size: '9pt', usage: 'Bibliography entries' },
  { name: 'Abstract', font: 'Merriweather', size: '10pt', usage: 'Abstract text' },
];

const pptSlides = [
  { name: 'Title Slide', purpose: 'Presentation title and author info' },
  { name: 'Section Divider', purpose: 'Transition between major sections' },
  { name: 'Content', purpose: 'Main content with bullet points' },
  { name: 'Two-Column', purpose: 'Side-by-side content layout' },
  { name: 'Data/Chart', purpose: 'Data visualization with chart placeholder' },
  { name: 'Image+Text', purpose: 'Large image with descriptive text' },
  { name: 'References', purpose: 'Bibliography and citations' },
  { name: 'Thank You / Q&A', purpose: 'Closing slide with contact info' },
];

type Tab = 'word' | 'powerpoint';

export default function Templates() {
  const [activeTab, setActiveTab] = useState<Tab>('word');

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <FadeIn>
        <div className="text-center mb-10">
          <h1 className="text-3xl sm:text-4xl font-bold text-slate-900">Templates</h1>
          <p className="text-slate-500 mt-2">Professional templates for academic publishing</p>
        </div>
      </FadeIn>

      {/* Tabs */}
      <FadeIn delay={0.1}>
        <div className="flex justify-center mb-10">
          <div className="inline-flex bg-slate-100 rounded-xl p-1">
            <button
              onClick={() => setActiveTab('word')}
              className={`px-6 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 ${
                activeTab === 'word'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-500 hover:text-slate-700'
              }`}
            >
              Word Template
            </button>
            <button
              onClick={() => setActiveTab('powerpoint')}
              className={`px-6 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 ${
                activeTab === 'powerpoint'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-500 hover:text-slate-700'
              }`}
            >
              PowerPoint Template
            </button>
          </div>
        </div>
      </FadeIn>

      {/* Word Template */}
      {activeTab === 'word' && (
        <div>
          <FadeIn>
            <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 sm:p-8 mb-8">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center text-xl">📝</div>
                <div>
                  <h2 className="text-xl font-semibold text-slate-900">Academic-Modern.dotx</h2>
                  <p className="text-sm text-slate-500">Word template with 10 pre-configured styles</p>
                </div>
              </div>
              <p className="text-slate-600 mb-4">
                Designed for academic papers, journal submissions, and research reports.
                Uses a combination of sans-serif headings (Montserrat) and serif body text (Merriweather)
                for optimal readability and professional appearance.
              </p>
              <div className="flex flex-wrap gap-2">
                <span className="px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-full">Merriweather 11pt body</span>
                <span className="px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-full">1.5 line spacing</span>
                <span className="px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-full">A4 format</span>
                <span className="px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-full">Optimized margins</span>
              </div>
            </div>
          </FadeIn>

          <FadeIn delay={0.1}>
            <h3 className="text-lg font-semibold text-slate-900 mb-4">Style Reference</h3>
            <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b border-slate-200">
                    <tr>
                      <th className="text-left px-4 py-3 font-semibold text-slate-700">Style Name</th>
                      <th className="text-left px-4 py-3 font-semibold text-slate-700">Font</th>
                      <th className="text-left px-4 py-3 font-semibold text-slate-700">Size</th>
                      <th className="text-left px-4 py-3 font-semibold text-slate-700">Usage</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {wordStyles.map((style) => (
                      <tr key={style.name} className="hover:bg-slate-50 transition-colors">
                        <td className="px-4 py-3 font-medium text-slate-900">{style.name}</td>
                        <td className="px-4 py-3 text-slate-600">{style.font}</td>
                        <td className="px-4 py-3 text-slate-600">{style.size}</td>
                        <td className="px-4 py-3 text-slate-500">{style.usage}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </FadeIn>
        </div>
      )}

      {/* PowerPoint Template */}
      {activeTab === 'powerpoint' && (
        <div>
          <FadeIn>
            <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 sm:p-8 mb-8">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center text-xl">🎨</div>
                <div>
                  <h2 className="text-xl font-semibold text-slate-900">Conference-Pro.potx</h2>
                  <p className="text-sm text-slate-500">PowerPoint template with 8 slide layouts</p>
                </div>
              </div>
              <p className="text-slate-600 mb-4">
                Conference-grade presentation template optimized for academic talks and research presentations.
                Features clean typography hierarchy and consistent visual language across all slide types.
              </p>
              <div className="flex flex-wrap gap-2">
                <span className="px-3 py-1 bg-purple-50 text-purple-700 text-xs font-medium rounded-full">16:9 widescreen</span>
                <span className="px-3 py-1 bg-purple-50 text-purple-700 text-xs font-medium rounded-full">Montserrat titles</span>
                <span className="px-3 py-1 bg-purple-50 text-purple-700 text-xs font-medium rounded-full">Inter body text</span>
                <span className="px-3 py-1 bg-purple-50 text-purple-700 text-xs font-medium rounded-full">8 slide masters</span>
              </div>
            </div>
          </FadeIn>

          <FadeIn delay={0.1}>
            <h3 className="text-lg font-semibold text-slate-900 mb-4">Slide Layouts</h3>
            <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {pptSlides.map((slide, i) => (
                <div key={slide.name} className="bg-white rounded-xl shadow-sm border border-slate-200 p-5 hover:shadow-md transition-shadow">
                  <div className="text-2xl mb-3">{['🎯', '📑', '📋', '📊', '📈', '🖼️', '📚', '🙏'][i]}</div>
                  <h4 className="font-semibold text-slate-900 mb-1">{slide.name}</h4>
                  <p className="text-xs text-slate-500">{slide.purpose}</p>
                </div>
              ))}
            </div>
          </FadeIn>
        </div>
      )}
    </div>
  );
}
