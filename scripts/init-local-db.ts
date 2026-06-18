import { existsSync, mkdirSync, readFileSync } from 'fs';
import path from 'path';
import Database from 'better-sqlite3';
import { loadEnvFile } from '../src/lib/env';

loadEnvFile();

const audioDataPath = path.resolve(process.env.AUDIO_DATA_PATH || 'data');
const dbPath = path.resolve(process.env.DB_PATH || path.join(audioDataPath, 'yomitan-audio.db'));
const sqlPath = path.resolve(process.env.SQL_PATH || path.join(audioDataPath, 'entry_and_pitch_db.sql'));

if (!existsSync(sqlPath)) {
    console.error(`SQL file not found at ${sqlPath}`);
    process.exit(1);
}

mkdirSync(path.dirname(dbPath), { recursive: true });
const db = new Database(dbPath);
const sql = readFileSync(sqlPath, 'utf8');
const hasTransaction = /^\s*BEGIN(?:\s+TRANSACTION)?\b/i.test(sql);
const importSql = hasTransaction ? sql : `BEGIN IMMEDIATE;\n${sql}\nCOMMIT;`;

console.log(`Initializing database at ${dbPath} using ${sqlPath}...`);
db.pragma('journal_mode = MEMORY');
db.pragma('synchronous = OFF');
db.pragma('temp_store = MEMORY');
db.pragma('cache_size = -200000');
db.pragma('locking_mode = EXCLUSIVE');
db.pragma('foreign_keys = OFF');

try {
    db.exec(importSql);
} catch (error) {
    if (db.inTransaction) {
        db.exec('ROLLBACK');
    }
    throw error;
} finally {
    db.pragma('locking_mode = NORMAL');
    db.pragma('synchronous = NORMAL');
    db.pragma('journal_mode = DELETE');
    db.close();
}
console.log('Database initialization complete.');
