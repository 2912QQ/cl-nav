// 用法：node tools/hash.mjs 你的新管理员密码   → 生成 admin.sql
import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
const pw = process.argv[2] || process.env.ADMIN_PW;
if (!pw) { console.error('请提供密码：node tools/hash.mjs 密码'); process.exit(1); }
const salt = randomBytes(16);
const h = pbkdf2Sync(pw, salt, 100000, 32, 'sha256');
const hash = `pbkdf2$100000$${salt.toString('base64')}$${h.toString('base64')}`;
writeFileSync('admin.sql', `UPDATE users SET password='${hash}' WHERE id=(SELECT MIN(id) FROM users);\n`);
console.log('已生成 admin.sql');
