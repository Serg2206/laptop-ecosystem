import FadeIn from '../components/FadeIn';

const fonts = [
  {
    name: 'Inter',
    category: 'Sans-serif',
    description: 'Clean, modern UI font optimized for screen readability.',
    weights: ['Regular', 'Medium', 'SemiBold', 'Bold'],
    usage: 'UI elements, tables, captions, navigation',
    import: "@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');",
  },
  {
    name: 'Montserrat',
    category: 'Sans-serif',
    description: 'Geometric sans-serif with professional character.',
    weights: ['Regular', 'Medium', 'SemiBold', 'Bold'],
    usage: 'Headings, titles, slide headers',
    import: "@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap');",
  },
  {
    name: 'Merriweather',
    category: 'Serif',
    description: 'Highly readable serif font designed for screens.',
    weights: ['Regular', 'Bold', 'Italic', 'Bold Italic'],
    usage: 'Body text, paragraphs, abstracts',
    import: "@import url('https://fonts.googleapis.com/css2?family=Merriweather:ital,wght@0,400;0,700;1,400;1,700&display=swap');",
  },
  {
    name: 'Crimson Text',
    category: 'Serif',
    description: 'Elegant serif font inspired by classic typography.',
    weights: ['Regular', 'SemiBold', 'Bold', 'Italic'],
    usage: 'Quotations, epigraphs, special emphasis',
    import: "@import url('https://fonts.googleapis.com/css2?family=Crimson+Text:ital,wght@0,400;0,600;0,700;1,400&display=swap');",
  },
  {
    name: 'Playfair Display',
    category: 'Display Serif',
    description: 'Sophisticated display font with high contrast.',
    weights: ['Regular', 'Bold', 'Italic', 'Bold Italic'],
    usage: 'Cover pages, presentation titles, special headings',
    import: "@import url('https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,700;1,400;1,700&display=swap');",
  },
  {
    name: 'Source Code Pro',
    category: 'Monospace',
    description: 'Professional monospace font for code and data.',
    weights: ['Regular', 'Medium', 'SemiBold', 'Bold'],
    usage: 'Code blocks, data tables, technical content',
    import: "@import url('https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;500;600;700&display=swap');",
  },
];

export default function Fonts() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <FadeIn>
        <div className="text-center mb-10">
          <h1 className="text-3xl sm:text-4xl font-bold text-slate-900">Font Collection</h1>
          <p className="text-slate-500 mt-2">6 font families, 24+ variants for professional publishing</p>
        </div>
      </FadeIn>

      {/* Font cards */}
      <div className="grid md:grid-cols-2 gap-6 mb-12">
        {fonts.map((font, i) => (
          <FadeIn key={font.name} delay={i * 0.1}>
            <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-6 hover:shadow-md transition-shadow">
              <div className="flex justify-between items-start mb-3">
                <div>
                  <h3 className="text-lg font-semibold text-slate-900">{font.name}</h3>
                  <span className="text-xs text-slate-400 uppercase tracking-wide">{font.category}</span>
                </div>
                <div className="flex flex-wrap gap-1 justify-end max-w-[50%]">
                  {font.weights.map((w) => (
                    <span key={w} className="px-2 py-0.5 bg-slate-100 text-slate-600 text-xs rounded">
                      {w}
                    </span>
                  ))}
                </div>
              </div>
              <p className="text-sm text-slate-600 mb-3">{font.description}</p>
              <p className="text-xs text-slate-500 mb-3">
                <span className="font-medium">Usage:</span> {font.usage}
              </p>
              <code className="block text-xs bg-slate-800 text-green-400 p-3 rounded-lg overflow-x-auto">
                {font.import}
              </code>
            </div>
          </FadeIn>
        ))}
      </div>

      {/* Reference table */}
      <FadeIn>
        <h2 className="text-xl font-semibold text-slate-900 mb-4">Quick Reference</h2>
        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 border-b border-slate-200">
                <tr>
                  <th className="text-left px-4 py-3 font-semibold text-slate-700">Font</th>
                  <th className="text-left px-4 py-3 font-semibold text-slate-700">Type</th>
                  <th className="text-left px-4 py-3 font-semibold text-slate-700">CSS Font Family</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {fonts.map((font) => (
                  <tr key={font.name} className="hover:bg-slate-50 transition-colors">
                    <td className="px-4 py-3 font-medium text-slate-900">{font.name}</td>
                    <td className="px-4 py-3 text-slate-600">{font.category}</td>
                    <td className="px-4 py-3">
                      <code className="text-xs bg-slate-100 px-2 py-1 rounded">&quot;{font.name}&quot;, {font.category === 'Monospace' ? 'monospace' : font.category === 'Serif' || font.category === 'Display Serif' ? 'serif' : 'sans-serif'}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </FadeIn>
    </div>
  );
}
