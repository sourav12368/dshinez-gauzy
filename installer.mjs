#!/usr/bin/env node
import { spawnSync, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { cp, mkdir, open, readFile, readdir, unlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const source = fileURLToPath(new URL('./runtime/', import.meta.url));
const dir = resolve('dshinez-gauzy');
const state = join(dir, '.env');
const help = 'Run the installer in the folder where you want the dshinez-gauzy project. Docker with Compose v2.20+ must be running. Use --no-open to skip opening the browser.';
const flags = process.argv.slice(2);

function docker(args, cwd, quiet = false) {
	const result = spawnSync('docker', args, { cwd, stdio: quiet ? 'pipe' : 'inherit', windowsHide: true });
	if (result.error || result.status !== 0) {
		throw new Error(quiet ? 'Start Docker Desktop or Docker Engine with Compose v2.20+ and run the command again.' : 'Docker ' + args.join(' ') + ' failed. Check the error above and rerun from the same folder.');
	}
}

function browser(url) {
	const [program, args] = process.platform === 'win32' ? ['rundll32.exe', ['url.dll,FileProtocolHandler', url]]
		: process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
	const child = spawn(program, args, { detached: true, stdio: 'ignore' });
	child.on('error', () => {});
	child.unref();
}

async function credentials() {
	try {
		const settings = Object.fromEntries((await readFile(state, 'utf8')).trim().split('\n').map(line => {
			const i = line.indexOf('=');
			return [line.slice(0, i), line.slice(i + 1).trimEnd()];
		}));
		if (!/^[1-9]\d{3,4}$/.test(settings.WEB_PORT) || +settings.WEB_PORT > 65535 || settings.LOCAL_URL !== 'http://127.0.0.1:' + settings.WEB_PORT) {
			throw new Error('Check WEB_PORT and LOCAL_URL in ' + state + '.');
		}
		return settings;
	} catch (error) {
		if (error.code !== 'ENOENT') throw error;
	}
	if ((await readdir(dir)).some(name => name !== '.installing')) throw new Error(dir + ' already exists. Run the installer from a different folder.');
	let email = 'admin@dshinez.local';
	let port = '4200';
	if (process.stdin.isTTY && process.stdout.isTTY) {
		const terminal = createInterface({ input: process.stdin, output: process.stdout });
		try {
			email = (await terminal.question('Admin email [' + email + '] ')).trim() || email;
			port = (await terminal.question('Browser port [' + port + '] ')).trim() || port;
		} finally {
			terminal.close();
		}
	}
	if (!/^[\w.+-]+@[\w.-]+\.[a-z]{2,}$/i.test(email)) throw new Error('Enter a valid admin email.');
	if (!/^[1-9]\d{3,4}$/.test(port) || +port > 65535) throw new Error('Enter a port between 1000 and 65535.');
	const settings = { WEB_PORT: port, LOCAL_URL: 'http://127.0.0.1:' + port, DEMO_SUPER_ADMIN_EMAIL: email };
	for (const key of ['DB_PASS', 'DEMO_SUPER_ADMIN_PASSWORD', 'DEMO_ADMIN_PASSWORD', 'DEMO_EMPLOYEE_PASSWORD']) {
		settings[key] = randomBytes(24).toString('hex');
	}
	for (const key of ['JWT_SECRET', 'JWT_REFRESH_TOKEN_SECRET', 'JWT_VERIFICATION_TOKEN_SECRET', 'EXPRESS_SESSION_SECRET']) {
		settings[key] = randomBytes(48).toString('hex');
	}
	await writeFile(state, Object.entries(settings).map(([key, value]) => key + '=' + value).join('\n') + '\n',
		{ flag: 'wx', mode: 0o600 });
	return settings;
}

async function waitForApp(url) {
	for (let i = 0; i < 75; i++) {
		try {
			const options = { signal: AbortSignal.timeout(3000) };
			const [app, api, wizard] = await Promise.all([
				fetch(url, options), fetch(url + '/api/health', options),
				fetch(url + '/assets/branding/dshinez/onboarding.html', options)
			]);
			if (app.ok && api.ok && wizard.ok) {
				const [html, health, guide] = await Promise.all([app.text(), api.json(), wizard.text()]);
				if (html.includes('class="dshinez-app"') && health.status === 'ok' && guide.includes('dshinez-onboarding')) return;
			}
		} catch {
			// Services are still starting.
		}
		await delay(2000);
	}
	throw new Error('Gauzy did not become ready. In ' + dir + ' run docker compose ps and docker compose logs api webapp.');
}

async function main() {
	if (flags.includes('--help') || flags.includes('-h')) {
		console.log(help);
		return;
	}
	if (flags.some(flag => flag !== '--no-open')) throw new Error(help);
	docker(['info', '--format', '{{.ServerVersion}}'], process.cwd(), true);
	docker(['compose', 'version'], process.cwd(), true);
	await mkdir(dir, { recursive: true, mode: 0o700 });
	const lockPath = join(dir, '.installing');
	const lock = await open(lockPath, 'wx').catch(error => {
		if (error.code === 'EEXIST') throw new Error('Setup is already running. If an earlier setup was interrupted, remove ' + lockPath + ' and retry.');
		throw error;
	});
	try {
		const config = await credentials();
		await cp(source, dir, { recursive: true });
		await writeFile(join(dir, '.gitignore'), '.env\n.installing\n', { flag: 'wx' }).catch(error => {
			if (error.code !== 'EEXIST') throw error;
		});
		const compose = (args) => docker(['compose', '--project-directory', dir, ...args], dir);
		compose(['config', '--quiet']);
		console.log('Downloading the current Ever Gauzy images…');
		compose(['pull', 'db', 'redis', 'api', 'worker', 'gateway']);
		console.log('Applying the D’Shinez theme…');
		compose(['build', '--pull', 'webapp']);
		compose(['up', '-d', '--no-build', '--pull', 'never']);
		console.log('Waiting for the Gauzy dashboard and setup guide…');
		await waitForApp(config.LOCAL_URL);
		const wizard = config.LOCAL_URL + '/assets/branding/dshinez/onboarding.html';
		console.log('\nSetup guide: ' + wizard + '\nFirst login: ' + config.DEMO_SUPER_ADMIN_EMAIL +
			'\nInitial password: ' + config.DEMO_SUPER_ADMIN_PASSWORD +
			'\nKeep the .env file private. Change the initial password after signing in.');
		if (!flags.includes('--no-open')) browser(wizard);
	} finally {
		await lock.close();
		await unlink(lockPath);
	}
}
main().catch(error => {
	console.error('D’Shinez setup: ' + error.message);
	process.exitCode = 1;
});
