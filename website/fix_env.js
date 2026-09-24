const fs = require('fs');
const { join } = require('path');

function getFiles(dir, files = []) {
  const fileList = fs.readdirSync(dir);
  for (const file of fileList) {
    const name = join(dir, file);
    if (fs.statSync(name).isDirectory()) {
      getFiles(name, files);
    } else if (name.endsWith('.ts')) {
      files.push(name);
    }
  }
  return files;
}

const files = getFiles('src/app/api');
let count = 0;

for (const file of files) {
  let content = fs.readFileSync(file, 'utf8');
  let changed = false;

  if (content.includes('const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL;')) {
    content = content.replace(
      'const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL;',
      `const BACKEND_URL = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\\/$/, '');`
    );
    changed = true;
  }

  if (content.includes('${process.env.NEXT_PUBLIC_BACKEND_URL}')) {
    content = content.replace(
      /\$\{process\.env\.NEXT_PUBLIC_BACKEND_URL\}/g,
      `\${(process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\\/$/, '')}`
    );
    changed = true;
  }

  if (changed) {
    fs.writeFileSync(file, content);
    count++;
    console.log('Fixed', file);
  }
}
console.log('Total fixed:', count);
