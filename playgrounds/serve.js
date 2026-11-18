// 临时静态服务器：只是为了把 agent.txt 送到手机上，用完 Ctrl+C 或关掉进程即可。
// 用法：node serve.js [端口]
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('.', import.meta.url))
const port = Number(process.argv[2] ?? 8099)
const types = { '.html': 'text/html; charset=utf-8', '.txt': 'text/plain; charset=utf-8', '.css': 'text/css' }

createServer(async (req, res) => {
  try {
    const url = decodeURIComponent((req.url ?? '/').split('?')[0])
    const rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '')
    const file = join(root, normalize(rel))
    if (!file.startsWith(root)) { res.writeHead(403).end('forbidden'); return }
    const body = await readFile(file)
    res.writeHead(200, {
      'content-type': types[extname(file)] ?? 'application/octet-stream',
      'cache-control': 'no-store',
    })
    res.end(body)
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }).end('not found')
  }
}).listen(port, '0.0.0.0', () => {
  console.log(`serving ${root} on http://0.0.0.0:${port}`)
})
