import { promises as fs } from 'fs';
import path from 'path';

class LocalR2Object {
    private readonly filePath: string;

    constructor(filePath: string) {
        this.filePath = filePath;
    }

    async blob(): Promise<Blob> {
        const data = await fs.readFile(this.filePath);
        return new Blob([data]);
    }
}

export class LocalR2Bucket {
    private readonly basePath: string;

    constructor(basePath: string) {
        this.basePath = path.resolve(basePath);
    }

    async get(key: string): Promise<LocalR2Object | null> {
        const filePath = this.resolveKeyPath(key);

        try {
            await fs.access(filePath);
        } catch (error: any) {
            if (error?.code === 'ENOENT') {
                return null;
            }
            throw error;
        }

        return new LocalR2Object(filePath);
    }

    async put(key: string, value: Blob): Promise<void> {
        const filePath = this.resolveKeyPath(key);
        await fs.mkdir(path.dirname(filePath), { recursive: true });
        const buffer = Buffer.from(await value.arrayBuffer());
        await fs.writeFile(filePath, buffer);
    }

    private resolveKeyPath(key: string): string {
        const normalizedKey = key.replace(/\\/g, '/').replace(/^\/+/, '');
        const resolvedPath = path.resolve(this.basePath, normalizedKey);
        const baseWithSeparator = this.basePath.endsWith(path.sep) ? this.basePath : `${this.basePath}${path.sep}`;

        if (!resolvedPath.startsWith(baseWithSeparator)) {
            throw new Error(`Invalid storage key: ${key}`);
        }

        return resolvedPath;
    }
}
