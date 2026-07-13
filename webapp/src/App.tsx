import { Routes, Route } from 'react-router-dom';
import Layout from './components/Layout';
import Home from './pages/Home';
import Templates from './pages/Templates';
import Fonts from './pages/Fonts';
import Dashboard from './pages/Dashboard';
import Workflow from './pages/Workflow';
import Health from './pages/Health';

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/templates" element={<Templates />} />
        <Route path="/fonts" element={<Fonts />} />
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/workflow" element={<Workflow />} />
        <Route path="/health" element={<Health />} />
      </Route>
    </Routes>
  );
}

export default App;
