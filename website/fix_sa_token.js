
const fs = require('fs');

const paths = [
  'src/app/superadmin/wallet-schemes/page.tsx',
  'src/app/superadmin/subscriptions/page.tsx',
  'src/app/superadmin/reports/page.tsx',
  'src/app/superadmin/payouts/page.tsx',
  'src/app/superadmin/appointments/page.tsx'
];

paths.forEach(p => {
  let content = fs.readFileSync(p, 'utf8');

  const authHeadersRegex = /const authHeaders = \(\): Record<string, string> => \{\s*const token = localStorage\.getItem\('sa_token'\);\s*return \{\s*'Content-Type': 'application\/json',\s*\.\.\.\(token \? \{ Authorization: \Bearer \$\{token\}\ \} : \{\}\),\s*\};\s*\};/g;
  content = content.replace(authHeadersRegex, \const authHeaders = (): Record<string, string> => ({\n    'Content-Type': 'application/json',\n  });\);

  // Fix appointments/page.tsx inline stuff
  content = content.replace(/const token = localStorage\.getItem\('sa_token'\);\s*const res = await fetch\(\\\/api\/proxy\/superadmin\/appointments\?\\\$\{queryParams\.toString\(\)\}\\\, \{\s*headers: \{\s*'Authorization': \Bearer \\\$\{token\}\\s*\}\s*\}\);/g,
    \const res = await fetch(\\\/api/proxy/superadmin/appointments?\\\\);\);
    
  content = content.replace(/const token = localStorage\.getItem\('sa_token'\);\s*const res = await fetch\('\/api\/proxy\/superadmin\/salons\?per_page=100', \{\s*headers: \{ 'Authorization': \Bearer \\\$\{token\}\ \}\s*\}\);/g,
    \const res = await fetch('/api/proxy/superadmin/salons?per_page=100');\);

  content = content.replace(/const token = localStorage\.getItem\('sa_token'\);\s*const res = await fetch\(\\\\\\$\{process\.env\.NEXT_PUBLIC_BACKEND_URL\}\/api\/superadmin\/appointments\/\\\$\{selectedAppointmentId\}\/add-service\\\, \{\s*method: 'POST',\s*headers: \{\s*'Content-Type': 'application\/json',\s*'Authorization': \Bearer \\\$\{token\}\\s*\},\s*body: JSON\.stringify\(\{\s*service_id: selectedServiceId,\s*provider_id: selectedProviderId\s*\}\)\s*\}\);/g,
    \const res = await fetch(\\\\/api/superadmin/appointments/\/add-service\\\, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            service_id: selectedServiceId,
            provider_id: selectedProviderId
          })
        });\);

  // Remove removeItem calls
  content = content.replace(/localStorage\.removeItem\('sa_token'\);\s*/g, '');

  fs.writeFileSync(p, content);
});
console.log('done');

