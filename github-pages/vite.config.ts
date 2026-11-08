import { defineConfig } from 'vitest/config';
import path from 'path';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
	base: '/steam-deck-smart-sleep/',
	plugins: [
		// The React and Tailwind plugins are both required for Make, even if
		// Tailwind is not being actively used – do not remove them
		react(),
		tailwindcss(),
	],
	resolve: {
		alias: {
			// Alias @ to the src directory
			'@': path.resolve(__dirname, './src'),
		},
	},

	// File types to support raw imports. Never add .css, .tsx, or .ts files to this.
	assetsInclude: ['**/*.svg', '**/*.csv'],

	test: {
		environment: 'jsdom',
		setupFiles: ['./src/test/setup.ts'],
		coverage: {
			provider: 'v8',
			// Only the files this project's own tests are responsible for; the
			// generated shadcn/ui components are not exercised.
			include: [
				'src/app/App.tsx',
				'src/app/commands.ts',
				'src/app/components/CommandBox.tsx',
			],
			thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 },
		},
	},
});
