import test from 'node:test';
import assert from 'node:assert/strict';
import { tools } from '../src/tools.js';
import { createServer } from '../src/server.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

test('20 strict business schemas reject unknown fields and invalid dates',()=>{
  assert.equal(tools.length,20);
  for(const t of tools) {
    assert.ok(t.description.length>30);
    assert.equal(t.schema.safeParse({sql:'select *'}).success,false);
    assert.ok(!/execute_sql|update_table|delete_rows/.test(t.name));
  }
  const calendar=tools.find(t=>t.name==='diurna_create_calendar_event')!;
  assert.equal(calendar.schema.safeParse({title:'x',date:'2026-02-30'}).success,false);
});
test('MCP initialize, listTools, tool mapping and business errors',async()=>{
  const calls:unknown[]=[];
  const server=createServer(async(command,input)=>{calls.push({command,input});return {schemaVersion:1,ok:false,error:{code:'NOT_FOUND',message:'Not found'}};});
  const [a,b]=InMemoryTransport.createLinkedPair();
  await server.connect(a);
  const client=new Client({name:'test',version:'1'});await client.connect(b);
  try {
    assert.equal((await client.listTools()).tools.length,20);
    const result=await client.callTool({name:'diurna_get_memo',arguments:{id:'20000000-0000-0000-0000-000000000001'}});
    assert.equal(result.isError,true);
    assert.deepEqual(calls,[{command:['memo','get'],input:{id:'20000000-0000-0000-0000-000000000001'}}]);
    assert.equal((result.structuredContent as {error:{code:string}}).error.code,'NOT_FOUND');
  } finally {await client.close();await server.close();}
});
