import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

test('real stdio server calls the compiled CLI and maps missing authentication',async()=>{
  const home=await mkdtemp(join(tmpdir(),'diurna-mcp-test-'));
  const env:Record<string,string>={};
  for(const [k,v] of Object.entries(process.env)) if(v!==undefined && !['SUPABASE_URL','SUPABASE_ANON_KEY','DIURNA_HOME','DIURNA_CLI'].includes(k)) env[k]=v;
  env.DIURNA_HOME=home;
  env.DIURNA_CLI=resolve('../packages/diurna_cli/build/bundle/bin/diurna.exe');
  const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('../src/index.js',import.meta.url))],env,stderr:'pipe'});
  const client=new Client({name:'stdio-test',version:'1.0.0'});
  try {
    await client.connect(transport);
    assert.equal((await client.listTools()).tools.length,20);
    const result=await client.callTool({name:'diurna_search',arguments:{query:'MCP'}});
    assert.equal(result.isError,true);
    assert.equal((result.structuredContent as {error:{code:string}}).error.code,'AUTH_REQUIRED');
  } finally {await client.close();await rm(home,{recursive:true,force:true});}
});
