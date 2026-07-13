import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Витрина публикуется как статика; HashRouter — пути работают с любого хостинга
  base: './',
});
