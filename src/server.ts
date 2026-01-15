import { createServer, IncomingMessage, ServerResponse } from 'http';
import router from './index';
import { createEnv, loadEnvFile } from './lib/env';

type PendingContext = {
    waitUntil: (promise: Promise<unknown>) => void;
    flush: () => void;
};

function createExecutionContext(): PendingContext {
    const pending: Promise<unknown>[] = [];
    return {
        waitUntil: (promise: Promise<unknown>) => {
            pending.push(promise.catch(() => undefined));
        },
        flush: () => {
            if (pending.length > 0) {
                void Promise.allSettled(pending);
            }
        },
    };
}

function toHeaders(headers: IncomingMessage['headers']): Headers {
    const result = new Headers();
    for (const [key, value] of Object.entries(headers)) {
        if (typeof value === 'string') {
            result.set(key, value);
        } else if (Array.isArray(value)) {
            result.set(key, value.join(','));
        }
    }
    return result;
}

async function readRequestBody(req: IncomingMessage): Promise<Buffer | undefined> {
    if (!req.method || req.method === 'GET' || req.method === 'HEAD') {
        return undefined;
    }

    return await new Promise((resolve, reject) => {
        const chunks: Buffer[] = [];
        req.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
        req.on('end', () => resolve(Buffer.concat(chunks)));
        req.on('error', reject);
    });
}

async function toFetchRequest(req: IncomingMessage, fallbackOrigin: string): Promise<Request> {
    const origin = req.headers.host ? `http://${req.headers.host}` : fallbackOrigin;
    const url = new URL(req.url || '/', origin);
    const body = await readRequestBody(req);
    const init: RequestInit = {
        method: req.method || 'GET',
        headers: toHeaders(req.headers),
    };

    if (body) {
        init.body = body;
        (init as { duplex?: 'half' }).duplex = 'half';
    }

    return new Request(url.toString(), init);
}

async function sendResponse(res: ServerResponse, response: Response): Promise<void> {
    res.statusCode = response.status;
    response.headers.forEach((value, key) => {
        res.setHeader(key, value);
    });

    if (response.body) {
        const buffer = Buffer.from(await response.arrayBuffer());
        res.end(buffer);
    } else {
        res.end();
    }
}

async function requestHandler(req: IncomingMessage, res: ServerResponse, env: Env, fallbackOrigin: string) {
    const context = createExecutionContext();

    try {
        const request = await toFetchRequest(req, fallbackOrigin);
        const response = await router.fetch(request, env, context);
        await sendResponse(res, response);
    } catch (error) {
        const message = error instanceof Error ? error.message : 'Unhandled server error';
        res.statusCode = 500;
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify({ message }));
    } finally {
        context.flush();
    }
}

function parsePort(value: string | undefined, fallback: number): number {
    if (!value) {
        return fallback;
    }

    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

loadEnvFile();
const DEFAULT_PORT = 8787;
const env = createEnv();
const host = process.env.HOST || '127.0.0.1';
const port = parsePort(process.env.PORT, DEFAULT_PORT);
const fallbackOrigin = `http://${host}:${port}`;
const server = createServer((req, res) => {
    void requestHandler(req, res, env, fallbackOrigin);
});

server.listen(port, host, () => {
    console.log(`Local Yomitan audio server listening on ${fallbackOrigin}`);
});
