export {};

declare global {
    interface Env {
        AUTHENTICATION_ENABLED: boolean;
        AWS_POLLY_ENABLED: boolean;
        API_KEYS: string;
        AWS_ACCESS_KEY_ID: string;
        AWS_SECRET_ACCESS_KEY: string;
        AUDIO_DATA_PATH: string;
        DB_PATH: string;
        yomitan_audio_r2_bucket: R2Bucket;
        yomitan_audio_d1_db: D1Database;
    }

    interface D1Result<T = unknown> {
        success: boolean;
        results: T[];
        error?: string;
    }

    interface D1PreparedStatement {
        bind(...params: unknown[]): D1PreparedStatement;
        all<T = unknown>(): Promise<D1Result<T>>;
    }

    interface D1Database {
        prepare(query: string): D1PreparedStatement;
    }

    interface R2Object {
        blob(): Promise<Blob>;
    }

    interface R2Bucket {
        get(key: string): Promise<R2Object | null>;
        put(key: string, value: Blob): Promise<void>;
    }

    interface ExecutionContext {
        waitUntil(promise: Promise<unknown>): void;
    }

    interface Request {
        apiKey?: string | string[];
    }
}
