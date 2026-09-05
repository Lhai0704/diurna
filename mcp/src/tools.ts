import { z } from 'zod';

const id = z.string().uuid();
const version = z.string().regex(/^[a-f0-9]{64}$/).describe('Exact version from the latest read; never invent it.');
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => {
  const d = new Date(`${v}T00:00:00Z`); return !isNaN(d.valueOf()) && d.toISOString().slice(0,10)===v;
}, 'Valid YYYY-MM-DD date required');
const timestamp = z.string().datetime({ offset: true });
const text = z.string().refine(s => s.trim().length>0, 'Must not be blank');
const page = { limit:z.number().int().min(1).max(200).optional(), offset:z.number().int().min(0).optional() };
const range = { from:date.optional(), to:date.optional() };
const target = { id, version };
const itemType = z.enum(['idea','action','research','resource']);
const column = z.enum(['focus','pending']);
export type ToolDefinition = { name:string; command:string[]; description:string; readOnly:boolean; schema:z.AnyZodObject };
const tool=(name:string,command:string,description:string,shape:z.ZodRawShape,readOnly=false):ToolDefinition => ({name:`diurna_${name}`,command:command.split(' '),description,readOnly,schema:z.object(shape).strict()});
export const tools:ToolDefinition[] = [
  tool('search','search','Search before editing. Results contain IDs and versions; ambiguous matches require clarification.',{query:text,modules:z.array(z.enum(['inbox','calendar','memos','diary'])).optional(),...range,includeArchived:z.boolean().optional(),...page},true),
  tool('list_inbox','inbox list','Read Inbox captures and relationships. Archived records are excluded by default. Use id to fetch an exact full item.',{id:id.optional(),column:column.optional(),type:itemType.optional(),topicId:id.optional(),archived:z.boolean().optional(),completed:z.boolean().optional(),...page},true),
  tool('create_inbox_item','inbox create','Quickly capture content in pending Inbox. Use Calendar for a task on a specific date.',{content:text,requestId:id.optional()}),
  tool('update_inbox_item','inbox update','Update an exact Inbox item. Only actions have dueDate, priority and completion. Topic conversion detaches children; versions prevent stale overwrites.',{...target,content:text.optional(),type:itemType.nullable().optional(),isTopic:z.boolean().optional(),dueDate:date.nullable().optional(),priority:z.number().int().min(1).max(3).nullable().optional(),completed:z.boolean().optional(),pinned:z.boolean().optional()}),
  tool('archive_inbox_item','inbox archive','Prefer archiving over deletion. archived=false restores. Archiving a Topic detaches its children; restoring does not recreate those links.',{...target,archived:z.boolean()}),
  tool('move_inbox_item','inbox move','Move an item to focus/pending before an exact peer ID, or to the end when omitted. Moving detaches its parent.',{...target,column,beforeId:id.nullable().optional()}),
  tool('assign_inbox_item_to_topic','inbox assign-topic','Assign to a live top-level Topic. null detaches. Self references and nested Topics are rejected.',{...target,topicId:id.nullable()}),
  tool('list_calendar','calendar list','Read date-based calendar tasks. date and from/to are mutually exclusive. Range endpoints are inclusive.',{id:id.optional(),date:date.optional(),...range,completed:z.boolean().optional(),...page},true),
  tool('create_calendar_event','calendar create','Create a task for an explicit YYYY-MM-DD date.',{title:text,date,note:z.string().nullable().optional(),remindAt:timestamp.nullable().optional(),requestId:id.optional()}),
  tool('update_calendar_event','calendar update','Update title, date or notes by exact ID and version. Omitted fields are preserved; null clears optional fields.',{...target,title:text.optional(),date:date.optional(),note:z.string().nullable().optional(),remindAt:timestamp.nullable().optional()}),
  tool('complete_calendar_event','calendar complete','Set completion explicitly. Search for the correct ID first; completed=false reopens.',{...target,completed:z.boolean()}),
  tool('list_memos','memo list','List long-lived notes in manual order. Use get for an exact memo.',page,true),
  tool('get_memo','memo get','Read a memo including full content and version before modifying it.',{id},true),
  tool('create_memo','memo create','Create a long-lived note. Title is required; body may be empty.',{title:text,content:z.string().optional(),requestId:id.optional()}),
  tool('update_memo','memo update','Update an exact memo. appendContent appends verbatim; content replaces. Never supply both. Preserve the version from the preceding read.',{...target,title:text.optional(),content:z.string().optional(),appendContent:z.string().optional()}),
  tool('reorder_memos','memo reorder','Move one memo before another exact ID, or to the end. Does not accept raw positions.',{...target,beforeId:id.nullable().optional()}),
  tool('list_diary','diary list','Read dated personal entries including content, mood and tags. For summaries, only read; paginate until nextOffset is null.',{...range,...page},true),
  tool('get_diary_entry','diary get','Read one full diary entry by exact ID.',{id},true),
  tool('create_diary_entry','diary create','Record experiences, reflections or mood on an explicit date. Title and body are required.',{date,title:text,content:text,mood:z.string().nullable().optional(),tags:z.array(z.string()).optional(),requestId:id.optional()}),
  tool('update_diary_entry','diary update','Update an exact diary entry with a previously read version; omit fields to preserve them.',{...target,date:date.optional(),title:text.optional(),content:text.optional(),mood:z.string().nullable().optional(),tags:z.array(z.string()).optional()}),
];
