import { spawnSync } from 'node:child_process';

const allowedLicenses = (process.env.ALLOWED_LICENSES ?? '')
  .split(';')
  .map((license) => license.trim())
  .filter(Boolean);

if (allowedLicenses.length === 0) {
  console.error('ALLOWED_LICENSES must contain at least one license.');
  process.exit(1);
}

const result = spawnSync('pnpm', ['licenses', 'list', '--json'], {
  encoding: 'utf8',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

if (result.status !== 0) {
  process.stderr.write(result.stderr);
  process.exit(result.status ?? 1);
}

const licenseGroups = JSON.parse(result.stdout);
const packages = Object.entries(licenseGroups).flatMap(([license, entries]) =>
  entries.map((entry) => ({ license, ...entry })),
);
const disallowed = packages.filter(
  ({ license }) =>
    !allowedLicenses.some((allowedLicense) => license.includes(allowedLicense)),
);

if (disallowed.length > 0) {
  console.error('Disallowed package licenses:');
  for (const entry of disallowed) {
    const versions = entry.versions.join(', ');
    console.error(`  ${entry.name}@${versions}: ${entry.license}`);
  }
  process.exit(1);
}

console.log(
  `License allowlist passed: ${packages.length} packages, ${Object.keys(licenseGroups).length} licenses.`,
);
