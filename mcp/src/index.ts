import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { cliBridge } from './bridge.js';
import { createServer } from './server.js';
const executable=process.env.DIURNA_CLI;
if(!executable) { process.stderr.write('Set DIURNA_CLI to the compiled Diurna executable.\n');process.exit(1); }
await createServer(cliBridge(executable)).connect(new StdioServerTransport());
