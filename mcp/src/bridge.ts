import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';

export type Envelope = {schemaVersion:1;ok:boolean;data?:Record<string,unknown>;error?:{code:string;message:string};meta?:Record<string,unknown>};
export type Execute = (command:string[],input:Record<string,unknown>)=>Promise<Envelope>;
export function cliBridge(executable:string):Execute {
  if(!isAbsolute(executable)) throw new Error('DIURNA_CLI must be an absolute path to the compiled CLI');
  let queue:Promise<unknown>=Promise.resolve();
  return (command,input) => {
    const run=async():Promise<Envelope> => {
      const body={...input};
      if(command.at(-1)==='create') body.requestId ??= randomUUID();
      return new Promise(resolve=>{
        let output='',done=false;
        const child=spawn(executable,[...command,'--json','--input-json'],{shell:false,windowsHide:true,stdio:['pipe','pipe','pipe']});
        const finish=(result:Envelope)=>{if(done)return;done=true;clearTimeout(timer);resolve(result);};
        const uncertain=(code:string,message:string):Envelope=>({schemaVersion:1,ok:false,error:{code,message},meta:{executionState:'unknown',requestId:body.requestId}});
        const timer=setTimeout(()=>{child.kill();finish(uncertain('TIMEOUT','Execution may have committed. Inspect data before retrying; reuse requestId for a create.'));},120_000);
        child.stdout.setEncoding('utf8');
        child.stdout.on('data',(chunk:string)=>{output+=chunk;if(output.length>8*1024*1024){child.kill();finish(uncertain('OUTPUT_LIMIT','Response exceeded limit; execution state is unknown.'));}});
        child.stderr.resume(); // Never forward tokens or arbitrary SDK diagnostics.
        child.on('error',()=>finish({schemaVersion:1,ok:false,error:{code:'CLI_UNAVAILABLE',message:'Cannot start configured Diurna CLI'}}));
        child.stdin.on('error',()=>{});
        child.on('close',()=>{
          try {
            const result=JSON.parse(output) as Envelope;
            if(result.schemaVersion!==1 || typeof result.ok!=='boolean') throw new Error();
            finish(result);
          } catch {finish(uncertain('INVALID_RESPONSE','CLI did not return a complete v1 envelope.'));}
        });
        child.stdin.end(JSON.stringify(body));
      });
    };
    const result=queue.then(run);queue=result.catch(()=>{});return result;
  };
}
