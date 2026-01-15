import { readFileSync, existsSync } from 'fs';
import path from 'path';
import { LocalD1Database } from './localD1Database';
import { LocalR2Bucket } from './localR2Bucket';

const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on']);

export function loadEnvFile(explicitPath?: string): void {
    const envPath = explicitPath || process.env.ENV_FILE || '.env';
    if (!existsSync(envPath)) {
        return;
    }

    const contents = readFileSync(envPath, 'utf8');
    for (const rawLine of contents.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#')) {
            continue;
        }

        const separatorIndex = line.indexOf('=');
        if (separatorIndex === -1) {
            continue;
        }

        const key = line.slice(0, separatorIndex).trim();
        let value = line.slice(separatorIndex + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
            value = value.slice(1, -1);
        }

        if (process.env[key] === undefined) {
            process.env[key] = value;
        }
    }
}

export function parseBoolean(value: string | undefined, fallback: boolean): boolean {
    if (value === undefined) {
        return fallback;
    }
    return TRUE_VALUES.has(value.trim().toLowerCase());
}

export function createEnv(): Env {
    const audioDataPath = path.resolve(process.env.AUDIO_DATA_PATH || 'data');
    const dbPath = path.resolve(process.env.DB_PATH || path.join(audioDataPath, 'yomitan-audio.db'));

    if (!existsSync(audioDataPath)) {
        throw new Error(`AUDIO_DATA_PATH does not exist: ${audioDataPath}`);
    }
    if (!existsSync(dbPath)) {
        throw new Error(`Database file not found at ${dbPath}. Run npm run db:init first.`);
    }

    const authenticationEnabled = parseBoolean(process.env.AUTHENTICATION_ENABLED, true);
    const apiKeys = process.env.API_KEYS || '';
    if (authenticationEnabled && apiKeys.trim() === '') {
        throw new Error('AUTHENTICATION_ENABLED is true but API_KEYS is empty.');
    }

    const awsPollyEnabled = parseBoolean(process.env.AWS_POLLY_ENABLED, false);
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID || '';
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY || '';
    if (awsPollyEnabled && (!accessKeyId || !secretAccessKey)) {
        throw new Error('AWS_POLLY_ENABLED is true but AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY is missing.');
    }

    return {
        AUTHENTICATION_ENABLED: authenticationEnabled,
        AWS_POLLY_ENABLED: awsPollyEnabled,
        API_KEYS: apiKeys,
        AWS_ACCESS_KEY_ID: accessKeyId,
        AWS_SECRET_ACCESS_KEY: secretAccessKey,
        AUDIO_DATA_PATH: audioDataPath,
        DB_PATH: dbPath,
        yomitan_audio_r2_bucket: new LocalR2Bucket(audioDataPath),
        yomitan_audio_d1_db: new LocalD1Database(dbPath),
    };
}
