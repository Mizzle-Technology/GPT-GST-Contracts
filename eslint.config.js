// eslint.config.js

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import prettierPlugin from 'eslint-plugin-prettier';
import mochaPlugin from 'eslint-plugin-mocha';
import js from '@eslint/js';
import prettierConfig from 'eslint-config-prettier';

// Reconstruct __dirname in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

export default [
  {
    ignores: ['node_modules/**', 'dist/**', 'build/**', 'coverage/**', '*.config.js'],
  },
  {
    files: ['**/*.js', '**/*.ts', '**/*.jsx', '**/*.tsx'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parser: tsParser,
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
      prettier: prettierPlugin,
      mocha: mochaPlugin,
    },
    rules: {
      // TypeScript Rules
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/no-explicit-any': 'warn',

      // JavaScript Rules
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-debugger': 'warn',

      // Prettier Integration
      'prettier/prettier': 'error',

      // Mocha Rules
      'mocha/no-exclusive-tests': 'error', // Prevent use of .only in tests
      'mocha/no-skipped-tests': 'warn', // Warn about skipped tests
      'mocha/no-global-tests': 'error', // Disallow global tests without a suite
      'mocha/no-hooks-for-single-case': 'warn', // Avoid hooks with a single test

      // Custom Rules
      eqeqeq: ['error', 'always'],
      curly: ['error', 'all'],
    },
    settings: {
      // Adjust project-specific settings
      'import/resolver': {
        node: {
          extensions: ['.js', '.jsx', '.ts', '.tsx'],
        },
      },
    },
  },
];
