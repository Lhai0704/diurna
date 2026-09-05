import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { tools } from './tools.js';
import type { Execute } from './bridge.js';
export function createServer(execute:Execute):McpServer {
  const server=new McpServer({name:'diurna',version:'1.0.0'});
  for(const tool of tools) {
    server.registerTool(tool.name,{
      description:tool.description,inputSchema:tool.schema,
      annotations:{readOnlyHint:tool.readOnly,destructiveHint:!tool.readOnly,idempotentHint:tool.readOnly,openWorldHint:false},
    },async(input)=>{
      const checked=tool.schema.parse(input);
      const result=await execute(tool.command,checked);
      return {isError:!result.ok,structuredContent:{...result},content:[{type:'text' as const,text:JSON.stringify(result)}]};
    });
  }
  return server;
}
