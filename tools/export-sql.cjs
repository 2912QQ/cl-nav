// 在旧设备容器里运行：docker exec -i nav-item node - < export-sql.cjs > data.sql
const sqlite3 = require('sqlite3');
const fs = require('fs');
const db = new sqlite3.Database('/app/database/nav.db', sqlite3.OPEN_READONLY);
const esc = v => v === null || v === undefined ? 'NULL' : typeof v === 'number' ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";
const tables = ['menus', 'sub_menus', 'users', 'cards', 'ads', 'friends'];
const out = [];
const next = i => {
  if (i === tables.length) {
    try {
      const w = JSON.parse(fs.readFileSync('/app/database/wallpaper.json', 'utf8'));
      if (w.url) out.push(`INSERT OR REPLACE INTO settings (key,value) VALUES ('wallpaper',${esc(JSON.stringify(w))});`);
    } catch (e) {}
    console.log(out.join('\n'));
    return;
  }
  db.all(`SELECT * FROM ${tables[i]}`, (err, rows) => {
    if (err) { console.error(err.message); process.exit(1); }
    rows.forEach(r => {
      const k = Object.keys(r);
      out.push(`INSERT INTO ${tables[i]} (${k.map(x => '"' + x + '"').join(',')}) VALUES (${k.map(x => esc(r[x])).join(',')});`);
    });
    next(i + 1);
  });
};
next(0);
