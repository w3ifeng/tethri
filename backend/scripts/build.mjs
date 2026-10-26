import { build } from 'esbuild';
import { mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
await mkdir('dist', {recursive:true});
await build({entryPoints:['src/neon.ts'],bundle:true,platform:'node',target:'node24',format:'esm',outfile:'dist/index.mjs',
  banner:{js:"import{createRequire as ___cr}from'node:module';const require=___cr(import.meta.url);"}});
execFileSync('/usr/bin/zip',['-j','function.zip','dist/index.mjs'],{stdio:'inherit'});
