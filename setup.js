'use strict';

// Auto-install deps if needed
const path = require('path');
const fs   = require('fs');
const os   = require('os');
const { spawnSync } = require('child_process');

if (!fs.existsSync(path.join(__dirname, 'node_modules', 'inquirer'))) {
  console.log('\n  Installing dependencies...\n');
  spawnSync('npm', ['install'], { cwd: __dirname, stdio: 'inherit', shell: true });
}

const inquirer = require('inquirer');

// ── Paths ──────────────────────────────────────────────────────────────────

const CLAUDE_DIR    = path.join(os.homedir(), '.claude');
const CFG_FILE      = path.join(CLAUDE_DIR, 'statusline-config.json');
const SETTINGS_FILE = path.join(CLAUDE_DIR, 'settings.json');
const PS1_DEST      = path.join(CLAUDE_DIR, 'statusline-wrapper.ps1');
const PS1_SRC       = path.join(__dirname, 'statusline-wrapper.ps1');

// ── ANSI ───────────────────────────────────────────────────────────────────

const R    = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM  = '\x1b[2m';
const CYN  = '\x1b[36m';
const YLW  = '\x1b[33m';
const GRN  = '\x1b[32m';
const RED  = '\x1b[31m';
const MAG  = '\x1b[35m';
const DCYN = '\x1b[96m';

// ── Emoji ──────────────────────────────────────────────────────────────────

const E = {
  robot: '\u{1F916}', bolt: '\u{26A1}',  timer: '\u{23F3}',
  brain: '\u{1F9E0}', warn: '\u{26A0}',  cal:   '\u{1F4C5}',
};

// ── Features definition ────────────────────────────────────────────────────

const FEATURES = [
  { key: 'showModel',     icon: E.robot, label: 'Model name',             short: 'Model'     },
  { key: 'showSession',   icon: E.bolt,  label: 'Session usage  (5h)',     short: 'Session'   },
  { key: 'showCountdown', icon: E.timer, label: 'Reset countdown',         short: 'Countdown' },
  { key: 'showContext',   icon: E.brain, label: 'Context window',          short: 'Context'   },
  { key: 'showCompact',   icon: E.warn,  label: 'Compact warning  (>80%)', short: 'Compact'   },
  { key: 'showWeekly',    icon: E.cal,   label: 'Weekly usage',            short: 'Weekly'    },
];

const DEFAULT_LAYOUT = [
  ['showModel', 'showSession', 'showCountdown'],
  ['showContext', 'showCompact', 'showWeekly'],
];

// ── Sample data for preview ────────────────────────────────────────────────

const SAMPLE = {
  model:       'Claude Sonnet 4.6',
  sessionLeft: 60,      // 40% used → 60% left
  ctxLeft:     18,      // 82% used → 18% left  (triggers compact warning)
  ctxSize:     200000,
  ctxRemain:   36000,
  weekUsed:    85,
  weekLeft:    15,
  countdown:   '2h 0m',
};

// ── Preview engine ─────────────────────────────────────────────────────────

function makeBar(pct, w) {
  const f = Math.min(w, Math.max(0, Math.round(pct / 100 * w)));
  return '#'.repeat(f) + '-'.repeat(w - f);
}

function barColor(pct) {
  return pct >= 60 ? GRN : pct >= 30 ? YLW : RED;
}

function fmtRemain(n) {
  if (n >= 10000) return `${Math.round(n / 1000)}k`;
  if (n >= 1000)  return `${(Math.round(n / 100) / 10).toFixed(1)}k`;
  return `${n}`;
}

function buildSeg(key, w, threshold) {
  switch (key) {
    case 'showModel':
      return `${E.robot} ${CYN}${BOLD}${SAMPLE.model}${R}`;

    case 'showSession':
      return `${E.bolt} ${barColor(SAMPLE.sessionLeft)}${makeBar(SAMPLE.sessionLeft, w)} ${SAMPLE.sessionLeft}%${R}`;

    case 'showCountdown':
      return `${E.timer} ${DIM}reset ${SAMPLE.countdown}${R}`;

    case 'showContext':
      return `${E.brain} ${barColor(SAMPLE.ctxLeft)}${makeBar(SAMPLE.ctxLeft, w)} ${SAMPLE.ctxLeft}%${R} ${DIM}(${fmtRemain(SAMPLE.ctxRemain)})${R}`;

    case 'showCompact':
      return SAMPLE.ctxLeft <= 20
        ? `${E.warn}  ${YLW}${BOLD}compact soon${R}`
        : null;

    case 'showWeekly':
      return SAMPLE.weekUsed >= threshold
        ? `${E.cal} ${barColor(SAMPLE.weekLeft)}${makeBar(SAMPLE.weekLeft, w)} ${SAMPLE.weekLeft}%${R}`
        : null;

    default:
      return null;
  }
}

function renderPreview(opts) {
  const SEP = `${DIM}|${R}`;
  const w   = opts.barWidth || 8;
  const thr = opts.weeklyThreshold !== undefined ? opts.weeklyThreshold : 80;
  const layout = (opts.layout && opts.layout.length > 0) ? opts.layout : DEFAULT_LAYOUT;

  const renderedLines = layout
    .map(lineKeys =>
      lineKeys
        .filter(k => opts[k] !== false)
        .map(k => buildSeg(k, w, thr))
        .filter(s => s !== null)
    )
    .filter(segs => segs.length > 0);

  const W = 60;
  console.log(`  ${DIM}+${'-'.repeat(W)}+${R}`);

  if (renderedLines.length === 0) {
    console.log(`  ${DIM}|  (nothing to display — all features OFF)${R}`);
  } else {
    for (const segs of renderedLines) {
      process.stdout.write(`  |  ${segs.join(`  ${SEP}  `)}${R}\n`);
    }
  }

  console.log(`  ${DIM}+${'-'.repeat(W)}+${R}`);
  console.log(`  ${DIM}Preview  ·  session 40%  ·  context 82%  ·  weekly 85%${R}`);
}

// ── UI helpers ─────────────────────────────────────────────────────────────

function banner(title) {
  const W = 60;
  const pad = Math.max(0, W - title.length);
  const l = ' '.repeat(Math.floor(pad / 2));
  const r = ' '.repeat(Math.ceil(pad / 2));
  console.log(`  ${DCYN}+${'-'.repeat(W)}+${R}`);
  console.log(`  ${CYN}|${l}${title}${r}|${R}`);
  console.log(`  ${DCYN}+${'-'.repeat(W)}+${R}`);
}

function hline() { console.log(`  ${'─'.repeat(62)}`); }

function step(msg) { console.log(`  ${CYN}>> ${msg}${R}`); }
function ok(msg)   { console.log(`  ${GRN}OK ${msg}${R}`); }
function warn(msg) { console.log(`  ${YLW}!! ${msg}${R}`); }
function fail(msg) { console.log(`  ${RED}XX ${msg}${R}`); process.exit(1); }

function screen(opts, stepLabel) {
  console.clear();
  console.log('');
  banner('CLAUDE CODE  —  STATUS BAR SETUP');
  console.log('');
  renderPreview(opts);
  console.log('');
  if (stepLabel) {
    console.log(`  ${YLW}${BOLD}${stepLabel}${R}`);
    hline();
    console.log('');
  }
}

// ── Config helpers ─────────────────────────────────────────────────────────

function loadExisting() {
  try {
    if (fs.existsSync(CFG_FILE)) return JSON.parse(fs.readFileSync(CFG_FILE, 'utf8'));
  } catch {}
  return null;
}

function ex(existing, key, def) {
  return (existing && existing[key] !== undefined) ? existing[key] : def;
}

// ── WIZARD ─────────────────────────────────────────────────────────────────

async function runWizard() {
  const existing = loadExisting();

  const opts = {
    showModel:       ex(existing, 'showModel',       true),
    showSession:     ex(existing, 'showSession',     true),
    showCountdown:   ex(existing, 'showCountdown',   true),
    showContext:     ex(existing, 'showContext',      true),
    showCompact:     ex(existing, 'showCompact',      true),
    showWeekly:      ex(existing, 'showWeekly',       true),
    weeklyThreshold: ex(existing, 'weeklyThreshold',  80),
    barWidth:        ex(existing, 'barWidth',          8),
    layout:          ex(existing, 'layout',           DEFAULT_LAYOUT),
  };

  // ── Step 1: Features ─────────────────────────────────────────────────────

  screen(opts, 'Step 1 / 4  —  Features');
  console.log(`  ${DIM}Space = toggle   Enter = confirm${R}\n`);

  const s1 = await inquirer.prompt([{
    type:    'checkbox',
    name:    'features',
    message: 'Which features should appear in your status bar?',
    choices: FEATURES.map(f => ({
      name:    `${f.icon}  ${f.label}`,
      value:   f.key,
      checked: opts[f.key],
    })),
  }]);

  FEATURES.forEach(f => { opts[f.key] = s1.features.includes(f.key); });

  // Prune layout of disabled features
  opts.layout = opts.layout
    .map(line => line.filter(k => opts[k]))
    .filter(line => line.length > 0);
  if (opts.layout.length === 0) opts.layout = DEFAULT_LAYOUT.map(l => l.filter(k => opts[k])).filter(l => l.length > 0);

  // ── Step 2: Weekly threshold ──────────────────────────────────────────────

  if (opts.showWeekly) {
    screen(opts, 'Step 2 / 4  —  Weekly visibility');

    const s2 = await inquirer.prompt([{
      type:    'list',
      name:    'weeklyThreshold',
      message: 'Show weekly usage bar:',
      default: String(opts.weeklyThreshold),
      choices: [
        { name: 'Always visible', value: '0' },
        new inquirer.Separator(),
        { name: 'From 50% usage', value: '50' },
        { name: 'From 60% usage', value: '60' },
        { name: 'From 70% usage', value: '70' },
        { name: 'From 80% usage  (default)', value: '80' },
        { name: 'From 90% usage', value: '90' },
      ],
    }]);

    opts.weeklyThreshold = parseInt(s2.weeklyThreshold, 10);
  }

  // ── Step 3: Layout ────────────────────────────────────────────────────────

  const enabledKeys = FEATURES.filter(f => opts[f.key]).map(f => f.key);

  if (enabledKeys.length > 0) {
    screen(opts, 'Step 3 / 4  —  Layout');

    const s3a = await inquirer.prompt([{
      type:    'list',
      name:    'numLines',
      message: 'How many lines for your status bar?',
      choices: [
        { name: '1 line   — all features on one row',              value: 1 },
        { name: '2 lines  — split into two rows  (default)',        value: 2 },
        { name: '3 lines  — three rows',                            value: 3 },
      ],
      default: Math.min(3, Math.max(1, opts.layout.length)),
    }]);

    const numLines  = s3a.numLines;
    const newLayout = [];
    let remaining   = [...enabledKeys];

    if (numLines === 1) {
      newLayout.push([...enabledKeys]);
    } else {
      for (let i = 0; i < numLines; i++) {
        if (remaining.length === 0) break;

        const isLast = i === numLines - 1;
        if (isLast) { newLayout.push([...remaining]); break; }

        // Preview: confirmed lines + remaining as tentative next line
        const previewLayout = [...newLayout, [...remaining]];
        screen({ ...opts, layout: previewLayout }, `Step 3 / 4  —  Line ${i + 1} of ${numLines}`);
        console.log(`  ${DIM}Choose which features go on line ${i + 1}. The rest will fill the next line(s).${R}\n`);

        const prevLine = (opts.layout[i] || []).filter(k => remaining.includes(k));

        const s3b = await inquirer.prompt([{
          type:     'checkbox',
          name:     'line',
          message:  `Line ${i + 1} — select features  (order here = display order):`,
          choices:  remaining.map(k => {
            const f = FEATURES.find(x => x.key === k);
            return { name: `${f.icon}  ${f.label}`, value: k, checked: prevLine.includes(k) };
          }),
          validate: ans => ans.length > 0 || 'Pick at least one feature for this line.',
        }]);

        newLayout.push(s3b.line);
        remaining = remaining.filter(k => !s3b.line.includes(k));
      }
    }

    opts.layout = newLayout;
  }

  // ── Step 4: Bar width ─────────────────────────────────────────────────────

  screen(opts, 'Step 4 / 4  —  Style');

  const s4 = await inquirer.prompt([{
    type:    'list',
    name:    'barWidth',
    message: 'Progress bar width:',
    choices: [6, 8, 10, 12].map(w => {
      const filled = Math.round(w * 0.6);
      return { name: `${String(w).padEnd(3)}  [${'#'.repeat(filled)}${'-'.repeat(w - filled)}]`, value: w };
    }),
    default: opts.barWidth,
  }]);

  opts.barWidth = s4.barWidth;

  // ── Final confirm ─────────────────────────────────────────────────────────

  screen(opts, null);
  console.log(`  ${GRN}${BOLD}Configuration ready.${R}\n`);

  const conf = await inquirer.prompt([{
    type:    'confirm',
    name:    'ok',
    message: 'Apply this configuration and install?',
    default: true,
  }]);

  if (!conf.ok) {
    console.log(`\n  ${DIM}Cancelled.${R}\n`);
    process.exit(0);
  }

  return opts;
}

// ── INSTALL mechanics ──────────────────────────────────────────────────────

async function install(opts) {
  console.clear();
  console.log('');
  banner('INSTALLING');
  console.log('');

  // Execution policy
  step('Execution policy');
  try {
    const r = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command',
      'Get-ExecutionPolicy -Scope CurrentUser'], { encoding: 'utf8' });
    const cur = (r.stdout || '').trim();
    if (cur === 'Restricted' || cur === 'Undefined') {
      spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command',
        'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force'],
        { stdio: 'inherit' });
      ok('Set to RemoteSigned.');
    } else {
      ok(`Already permissive (${cur}) — no change.`);
    }
  } catch (e) { warn(`Execution policy: ${e.message}`); }
  hline();

  // ~/.claude dir
  step('Preparing ~/.claude directory');
  try { fs.mkdirSync(CLAUDE_DIR, { recursive: true }); ok(`Ready: ${CLAUDE_DIR}`); }
  catch (e) { fail(`Cannot create ~/.claude: ${e.message}`); }
  hline();

  // Copy wrapper
  step('Installing statusline-wrapper.ps1');
  try { fs.copyFileSync(PS1_SRC, PS1_DEST); ok('Copied wrapper.'); }
  catch (e) { fail(`Copy failed: ${e.message}`); }

  spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command',
    `Unblock-File -Path "${PS1_DEST}"`], { encoding: 'utf8' });
  ok('Unblocked.');
  hline();

  // Save config
  step('Saving statusline-config.json');
  try {
    fs.writeFileSync(CFG_FILE, JSON.stringify(opts, null, 2), 'utf8');
    ok('Config saved.');
  } catch (e) { warn(`Config save failed: ${e.message}`); }
  hline();

  // Patch settings.json
  step('Patching Claude Code settings.json');

  const cmdValue = {
    type:    'command',
    command: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${PS1_DEST}"`,
  };

  let settingsObj = {};
  if (fs.existsSync(SETTINGS_FILE)) {
    const bk = `${SETTINGS_FILE}.backup_${new Date().toISOString().replace(/[:.]/g, '-')}`;
    fs.copyFileSync(SETTINGS_FILE, bk);
    ok(`Backup: ${path.basename(bk)}`);
    try { settingsObj = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')); }
    catch { warn('Could not parse settings.json — will recreate.'); }

    if (settingsObj.statusLine && settingsObj.statusLine.command &&
        !settingsObj.statusLine.command.includes('statusline-wrapper.ps1')) {
      console.log('');
      warn(`statusLine already set by another tool:\n    ${DIM}${settingsObj.statusLine.command}${R}`);
      const ow = await inquirer.prompt([{ type: 'confirm', name: 'ok', message: 'Overwrite?', default: true }]);
      if (!ow.ok) { warn('Skipped. Edit settings.json manually.'); return; }
    }
  }

  settingsObj.statusLine = cmdValue;
  fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settingsObj, null, 2), 'utf8');
  ok('settings.json updated.');

  // Race check
  const verify = fs.readFileSync(SETTINGS_FILE, 'utf8');
  if (!verify.includes('statusline-wrapper.ps1')) {
    console.log(`\n  ${RED}${BOLD}RACE CONDITION!${R} ${YLW}Claude Code overwrote settings.json.`);
    console.log(`  Close Claude Code completely, then re-run.${R}\n`);
  }
  hline();

  // Test wrapper
  step('Testing wrapper (-Test mode)');
  const t = spawnSync('powershell',
    ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', PS1_DEST, '-Test'],
    { encoding: 'utf8' });
  if (t.stdout && t.stdout.trim()) {
    ok('Output:');
    t.stdout.trim().split('\n').forEach(l => console.log(`    ${l}`));
  } else {
    warn('No output — check wrapper manually.');
  }
  hline();

  console.log('');
  banner('ALL DONE');
  console.log('');
  console.log(`  ${GRN}Restart Claude Code to activate your status bar.${R}\n`);
  console.log(`  ${DIM}Installed : ${CLAUDE_DIR}${R}`);
  console.log(`  ${DIM}Config    : statusline-config.json${R}`);
  console.log('');
}

// ── UNINSTALL ──────────────────────────────────────────────────────────────

async function uninstall() {
  console.clear();
  console.log('');
  banner('UNINSTALLING');
  console.log('');

  if (fs.existsSync(SETTINGS_FILE)) {
    const bk = `${SETTINGS_FILE}.backup_${Date.now()}`;
    fs.copyFileSync(SETTINGS_FILE, bk);
    ok(`Backed up: ${path.basename(bk)}`);
    try {
      const s = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8'));
      delete s.statusLine;
      fs.writeFileSync(SETTINGS_FILE, JSON.stringify(s, null, 2), 'utf8');
      ok('Removed statusLine from settings.json.');
    } catch { warn('Could not patch settings.json.'); }
  } else {
    warn('settings.json not found.');
  }

  for (const f of [PS1_DEST, CFG_FILE, path.join(CLAUDE_DIR, 'statusline-command.sh')]) {
    if (fs.existsSync(f)) { fs.unlinkSync(f); ok(`Deleted: ${path.basename(f)}`); }
  }

  console.log('');
  banner('ALL DONE');
  console.log('');
  console.log(`  ${GRN}Restart Claude Code to complete removal.${R}\n`);
}

// ── CLAUDE RUNNING CHECK ───────────────────────────────────────────────────

function claudeRunning() {
  const r = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command',
    'Get-Process -Name claude,claude-code,Claude -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name'],
    { encoding: 'utf8' });
  return !!(r.stdout && r.stdout.trim());
}

// ── MAIN MENU ──────────────────────────────────────────────────────────────

async function mainMenu() {
  console.clear();
  console.log('');
  banner('CLAUDE CODE  —  STATUS BAR');
  console.log('');
  console.log(`  ${CYN}[1]  Install       Set up the status bar${R}`);
  console.log(`  ${CYN}[2]  Uninstall     Remove the status bar${R}`);
  console.log(`  ${DIM}[Q]  Quit${R}`);
  console.log('');
  hline();
  console.log('');

  const ans = await inquirer.prompt([{
    type:    'list',
    name:    'action',
    message: 'What would you like to do?',
    choices: [
      { name: 'Install', value: 'install' },
      { name: 'Uninstall', value: 'uninstall' },
      new inquirer.Separator(),
      { name: 'Quit', value: 'quit' },
    ],
  }]);

  return ans.action;
}

// ── ENTRY POINT ────────────────────────────────────────────────────────────

async function main() {
  const arg = process.argv[2];

  if (arg === 'uninstall') { await uninstall(); return; }
  if (arg === 'install')   { /* fall through to install flow */ }

  let action = arg || null;

  if (!action) {
    action = await mainMenu();
  }

  if (action === 'quit' || action === 'Q') process.exit(0);

  if (action === 'uninstall') { await uninstall(); return; }

  // Install flow
  if (claudeRunning()) {
    console.clear();
    console.log('');
    banner('WARNING');
    console.log('');
    console.log(`  ${RED}Claude Code appears to be running!${R}`);
    console.log(`  ${YLW}It will overwrite settings.json right after we write it.${R}`);
    console.log(`  ${YLW}Close Claude Code completely (window + tray), then re-run.${R}\n`);
    const cont = await inquirer.prompt([{ type: 'confirm', name: 'ok', message: 'Continue anyway?', default: false }]);
    if (!cont.ok) { console.log(`\n  ${DIM}Aborted.${R}\n`); process.exit(0); }
  }

  const opts = await runWizard();
  await install(opts);
}

main().catch(e => { console.error(e); process.exit(1); });
