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

console.log(`Initializing database at ${dbPath} using ${sqlPath}...`);
db.exec(sql);
db.close();
console.log('Database initialization complete.');
