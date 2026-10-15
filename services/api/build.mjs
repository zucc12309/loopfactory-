// Bundles the API (including workspace packages) into dist/server.js; node_modules stay external.
import { build } from 'esbuild';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const workspace = {
  '@loopfactory/engine': resolve(root, 'packages/engine/src/index.ts'),
  '@loopfactory/engine/levels/curated.json': resolve(root, 'packages/engine/levels/curated.json'),
  '@loopfactory/contracts': resolve(root, 'packages/contracts/src/index.ts'),
  '@loopfactory/contracts/data/achievements.json': resolve(root, 'packages/contracts/data/achievements.json'),
};
await build({
  entryPoints: ['src/server.ts', 'src/scripts/seed.ts', 'src/scripts/maintenance.ts', 'src/scripts/pregenerate-daily.ts'],
  outdir: 'dist',
  outbase: 'src',
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'esm',
  sourcemap: true,
  packages: 'external',
  plugins: [{
    name: 'bundle-workspace',
    setup(b) {
      // Keep npm packages external but inline our own @loopfactory/* workspace packages (TS sources).
      b.onResolve({ filter: /^@loopfactory\// }, (args) => {
        const path = workspace[args.path];
        if (!path) throw new Error(`Unknown workspace import ${args.path}`);
        return { path };
      });
    },
  }],
  banner: { js: "import { createRequire } from 'module'; const require = createRequire(import.meta.url);" },
  logLevel: 'info',
});
