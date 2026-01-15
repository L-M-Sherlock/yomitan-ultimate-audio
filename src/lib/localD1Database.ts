import Database from 'better-sqlite3';

class LocalPreparedStatement {
    private readonly statement: Database.Statement;
    private boundParams: unknown[] = [];

    constructor(statement: Database.Statement) {
        this.statement = statement;
    }

    bind(...params: unknown[]): LocalPreparedStatement {
        this.boundParams = params;
        return this;
    }

    async all<T = unknown>(): Promise<D1Result<T>> {
        try {
            const results = this.statement.all(...this.boundParams) as T[];
            return { success: true, results };
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            return { success: false, results: [], error: message };
        }
    }
}

export class LocalD1Database {
    private readonly db: Database.Database;

    constructor(dbPath: string) {
        this.db = new Database(dbPath);
    }

    prepare(query: string): LocalPreparedStatement {
        const statement = this.db.prepare(query);
        return new LocalPreparedStatement(statement);
    }
}
