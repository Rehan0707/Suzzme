import { mkdir, copyFile, writeFile, readFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const deploymentFiles = Object.freeze(['server.mjs', 'notion-read.mjs', 'hosted.mjs', 'package.json',
  'setup.mjs', 'setup.test.mjs', 'server.test.mjs', 'deployment.test.mjs', 'prepare-render.mjs',
  '.env.example', 'check-config.mjs', 'render.yaml', 'README.md', 'RENDER-DEPLOYMENT.md']);
export async function prepareDeployment(destination) {
  await mkdir(destination); // Refuse existing destinations rather than merge unknown files.
  const files = {};
  for (const name of deploymentFiles) {
    const source = new URL(name, import.meta.url); const target = new URL(name, destination);
    await copyFile(source, target, constants.COPYFILE_EXCL);
    files[name] = createHash('sha256').update(await readFile(target)).digest('hex');
  }
  await writeFile(new URL('.gitignore', destination), '.env*\n!.env.example\nnode_modules/\n', { flag: 'wx' });
  await writeFile(new URL('manifest.json', destination), JSON.stringify({ secretFilesIncluded: false, files }, null, 2) + '\n', { flag: 'wx' });
  return files;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const target = new URL('../Release/ConnectorServer-render/', import.meta.url);
  try {
    const files = await prepareDeployment(target);
    console.log('Prepared connector-only Render bundle: ' + target.pathname);
    console.log('Copied ' + Object.keys(files).length + ' allowlisted files. No credentials included; nothing uploaded.');
  } catch {
    console.error('Bundle preparation did not complete. Destination must not exist; no existing files are overwritten.');
    process.exitCode = 1;
  }
}
