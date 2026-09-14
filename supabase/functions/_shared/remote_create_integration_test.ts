import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import postgres from "npm:postgres@3.4.5";
import { db } from "./db.ts";
import { writeTokenBundle } from "./credentials.ts";
import { reconcileExternalObject } from "./remote_create.ts";
import {
  applyGoogleEvent,
  processGoogleIncrementalWork,
} from "./google_worker.ts";
import { bootstrapGoogleConnection } from "./google_bootstrap.ts";
import { bootstrapNotionConnection } from "./notion_bootstrap.ts";
import { processNotionPageWork } from "./notion_worker.ts";
import { repairNotionConnection } from "./notion_repair.ts";
import { discoverNotionPages } from "./notion_discovery.ts";
import { withConnectionInboundLock } from "./inbound_work.ts";
import { GoogleSession } from "./google_auth.ts";
import { pushGoogle } from "./google_export.ts";
import { decideOutbound } from "./outbound_skip.ts";
import type { GoogleEvent } from "./google_import.ts";
import type { NotionBlock, NotionPage } from "./notion_import.ts";

const testUrl = Deno.env.get("DIURNA_TEST_DB_URL");
Deno.test({
  name: "remote create: real isolated PostgreSQL + mocked provider transport",
  ignore: !testUrl,
  fn: async (t) => {
    const parsed = new URL(testUrl!);
    if (
      parsed.hostname !== "127.0.0.1" || parsed.port !== "55439" ||
      !/^\/[a-z][a-z0-9_]*_test$/.test(parsed.pathname)
    ) {
      throw new Error(
        "Only the explicit isolated loopback test database is allowed",
      );
    }
    const previousUrl = Deno.env.get("SUPABASE_DB_URL");
    const previousKey = Deno.env.get("INTEGRATION_TOKEN_KEY");
    Deno.env.set("SUPABASE_DB_URL", testUrl!);
    Deno.env.set("INTEGRATION_TOKEN_KEY", "isolated-remote-create-fixture");
    const sql = db();
    const user = crypto.randomUUID(),
      foreignUser = crypto.randomUUID(),
      google = crypto.randomUUID(),
      notion = crypto.randomUUID();
    const inbox = crypto.randomUUID(),
      memo = crypto.randomUUID(),
      diary = crypto.randomUUID();
    const container = { inbox_ds: inbox, memo_ds: memo, diary_ds: diary };
    const event = (id: string): GoogleEvent => ({
      id,
      summary: "Remote day",
      start: { date: "2026-09-10" },
      end: { date: "2026-09-11" },
      etag: `${id}-1`,
      updated: "2026-09-10T00:00:00Z",
    });
    const paragraph = (content: string): NotionBlock => ({
      type: "paragraph",
      paragraph: { rich_text: [{ type: "text", text: { content } }] },
    });
    const pages = new Map<
      string,
      { page: NotionPage; blocks: NotionBlock[] }
    >();
    function page(
      source: string,
      title = "Remote page",
      blocks: NotionBlock[] = [],
    ): string {
      const id = crypto.randomUUID();
      pages.set(id, {
        page: {
          id,
          parent: { type: "data_source_id", data_source_id: source },
          last_edited_time: "2026-09-10T00:00:00Z",
          properties: {
            title: { title: [{ type: "text", text: { content: title } }] },
          },
        },
        blocks,
      });
      return id;
    }
    let failMetadata = false, metadataWrites = 0;
    const notionFetch = async (
      url: string,
      init?: RequestInit,
    ): Promise<Response> => {
      const parts = new URL(url).pathname.split("/");
      if (parts[2] === "data_sources") {
        return Response.json({
          results: [...pages.values()].filter((p) =>
            p.page.parent?.data_source_id === parts[3]
          ).map((p) => ({ id: p.page.id })),
          has_more: false,
        });
      }
      const found = pages.get(parts[3]);
      if (!found) return new Response(null, { status: 404 });
      if (parts[2] === "blocks") {
        return Response.json({ results: found.blocks, has_more: false });
      }
      if (init?.method === "PATCH") {
        metadataWrites++;
        const body = JSON.parse(String(init.body));
        assertEquals(Object.keys(body), ["properties"]);
        assertEquals(Object.keys(body.properties).sort(), [
          "Diurna ID",
          "Revision",
        ]);
        if (failMetadata) {
          return new Response(null, { status: 503 });
        }
        Object.assign(found.page.properties!, body.properties);
        found.page.last_edited_time = "2026-09-10T00:01:00Z";
      }
      return Response.json(found.page);
    };
    const runPage = (pageId: string) =>
      processNotionPageWork({
        connectionId: notion,
        pageId,
        eventType: "page.created",
        fetchImpl: notionFetch,
      });
    const mapping = async (connectionId: string, externalId: string) =>
      (await sql`select * from public.external_sync_links
    where connection_id=${connectionId}::uuid and external_id=${externalId}`)[
        0
      ];
    try {
      await sql`insert into auth.users(id) values(${user}::uuid),(${foreignUser}::uuid)`;
      await sql`insert into public.integration_connections(id,user_id,provider,status,inbound_status,container) values
      (${google}::uuid,${user}::uuid,'google','connected','active','{"calendar_id":"managed"}'::jsonb),
      (${notion}::uuid,${user}::uuid,'notion','connected','active',${
        sql.json(container)
      }::jsonb)`;
      await writeTokenBundle(notion, {
        access_token: "fixture",
        refresh_token: "fixture",
      }, null);

      await t.step(
        "Google create, duplicate, subsequent edit, outbound PATCH",
        async () => {
          assertEquals(
            (await applyGoogleEvent(google, event("manual"), "managed")).result,
            "created",
          );
          const first = await mapping(google, "manual");
          await applyGoogleEvent(google, event("manual"), "managed");
          assertEquals(
            (await mapping(google, "manual")).entity_id,
            first.entity_id,
          );
          assertEquals(
            (await applyGoogleEvent(google, {
              ...event("manual"),
              summary: "Edited",
              etag: "manual-2",
              updated: "2026-09-10T00:02:00Z",
            }, "managed")).result,
            "applied",
          );
          const linked = await mapping(google, "manual");
          const outboundLink = {
            ...linked,
            last_synced_revision: Number(linked.last_synced_revision),
            sync_status: String(linked.sync_status),
          };
          assert(
            decideOutbound(outboundLink, Number(linked.last_synced_revision))
              .skip,
          );
          await sql.begin(async (tx) => {
            await tx`select set_config('diurna.sync_protocol','2',true)`;
            await tx`update public.calendar_events set title='Local',revision=revision+1 where id=${linked.entity_id}::uuid`;
          });
          const [row] =
            await sql`select *,event_date::text as event_date from public.calendar_events where id=${linked.entity_id}::uuid`;
          assert(!decideOutbound(outboundLink, Number(row.revision)).skip);
          const requests: Array<{ url: string; method: string | undefined }> =
            [];
          const session = new GoogleSession(
            google,
            { access_token: "fixture", refresh_token: "fixture" },
            new Date(Date.now() + 3600000),
            async (input, init) => {
              requests.push({ url: String(input), method: init?.method });
              return Response.json({ id: "manual" });
            },
          );
          await pushGoogle({
            row: row as typeof row & { id: string },
            link: {
              entity_id: String(linked.entity_id),
              external_id: "manual",
            },
            tokens: "fixture",
            connection: { container: { calendar_id: "managed" } },
            googleAuth: session,
          });
          assertEquals(requests.length, 1);
          assertEquals(requests[0].method, "PATCH");
          assert(requests[0].url.endsWith("/events/manual"));
        },
      );

      await t.step(
        "Google unsupported, invalid/nonexistent ID, foreign user spoof and recover",
        async () => {
          for (
            const remote of [
              {
                ...event("timed"),
                start: { dateTime: "2026-09-10T12:00:00Z" },
              },
              { ...event("recurring"), recurrence: ["RRULE:FREQ=DAILY"] },
              { ...event("instance"), recurringEventId: "master" },
              { ...event("cancelled"), status: "cancelled" },
            ]
          ) {
            assertEquals(
              (await applyGoogleEvent(google, remote, "managed")).result,
              "ignored",
            );
            assertEquals(await mapping(google, remote.id!), undefined);
          }
          const foreign = crypto.randomUUID();
          await sql.begin(async (tx) => {
            await tx`select set_config('diurna.sync_protocol','2',true)`;
            await tx`insert into public.calendar_events(id,user_id,title,event_date) values(${foreign}::uuid,${foreignUser}::uuid,'Foreign','2026-09-10')`;
          });
          for (const candidate of ["invalid", crypto.randomUUID(), foreign]) {
            const remote = {
              ...event(crypto.randomUUID()),
              extendedProperties: { private: { diurnaId: candidate } },
            };
            assertEquals(
              (await applyGoogleEvent(google, remote, "managed")).result,
              "created",
            );
            const link = await mapping(google, remote.id!);
            assert(link.entity_id !== candidate);
            assertEquals(link.user_id, user);
          }
          const created = await applyGoogleEvent(
            google,
            event("recover"),
            "managed",
          );
          const link = await mapping(google, "recover");
          assertEquals(created.result, "created");
          await sql`delete from public.external_sync_links where id=${link.id}::uuid`;
          const recovered = await applyGoogleEvent(google, {
            ...event("recover"),
            extendedProperties: {
              private: { diurnaId: String(link.entity_id) },
            },
          }, "managed");
          assertEquals(recovered.result, "recovered");
          assertEquals(
            (await mapping(google, "recover")).entity_id,
            link.entity_id,
          );
        },
      );

      await t.step(
        "two independent SQL sessions serialize create and return identical mapping",
        async () => {
          const first = postgres(testUrl!, { max: 1, prepare: false }),
            second = postgres(testUrl!, { max: 1, prepare: false });
          try {
            const call = (tx: postgres.Sql | postgres.TransactionSql) =>
              tx`select integrations.reconcile_external_object(
          ${google}::uuid,'google','managed','calendar_events','concurrent',null,
          '{"title":"Concurrent","event_date":"2026-09-10"}'::jsonb,'{}'::jsonb,null,null) as r`;
            let inserted!: () => void;
            const started = new Promise<void>((resolve) => inserted = resolve);
            const a = first.begin(async (tx) => {
              const result = await call(tx);
              inserted();
              await tx`select pg_sleep(0.15)`;
              return result;
            });
            await started;
            const b = call(second);
            const [left, right] = await Promise.all([a, b]);
            assertEquals(left[0].r.entity_id, right[0].r.entity_id);
            assertEquals(right[0].r.result, "existing");
            assertEquals(
              Number(
                (await sql`select count(*) as n from public.calendar_events where user_id=${user}::uuid and title='Concurrent'`)[
                  0
                ].n,
              ),
              1,
            );
          } finally {
            await first.end();
            await second.end();
          }
        },
      );

      await t.step(
        "Google bootstrap, incremental replay and 410 resync use same identity",
        async () => {
          await sql`insert into integrations.provider_watches(connection_id,provider,channel_id,channel_token,calendar_id,status,resource_id)
        values(${google}::uuid,'google',${crypto.randomUUID()},'fixture','managed','active','fixture-resource')`;
          let expire = false;
          const listed = [event("bootstrap")];
          const session = new GoogleSession(
            google,
            { access_token: "fixture", refresh_token: "fixture" },
            new Date(Date.now() + 3600000),
            async (input) => {
              const url = new URL(String(input));
              assert(url.pathname.includes("/calendars/managed/events"));
              if (expire && url.searchParams.has("syncToken")) {
                expire = false;
                return new Response(null, { status: 410 });
              }
              return Response.json({
                items: listed,
                nextSyncToken: "sync-fixture",
              });
            },
          );
          await sql`update public.integration_connections set inbound_status='bootstrapping' where id=${google}::uuid`;
          await bootstrapGoogleConnection({
            connectionId: google,
            session,
            createWatch: false,
          });
          const before = await mapping(google, "bootstrap");
          assert(before);
          await processGoogleIncrementalWork({ connectionId: google, session });
          expire = true;
          const result = await processGoogleIncrementalWork({
            connectionId: google,
            session,
          });
          assert(result.fullResync);
          assertEquals(
            (await mapping(google, "bootstrap")).entity_id,
            before.entity_id,
          );
        },
      );

      await t.step(
        "Notion three modules, duplicate + metadata echo after local edit",
        async () => {
          const inboxPage = page(inbox),
            memoPage = page(memo, "Memo", [paragraph("one"), paragraph("two")]),
            diaryPage = page(diary, "Diary", [paragraph("day")]);
          Object.assign(pages.get(diaryPage)!.page.properties!, {
            Date: { date: { start: "2026-09-10" } },
            Mood: { rich_text: [{ text: { content: "happy" } }] },
          });
          for (const id of [inboxPage, memoPage, diaryPage]) {
            assertEquals((await runPage(id)).result, "created");
          }
          const link = await mapping(notion, memoPage);
          assertEquals(
            (await sql`select content from public.memos where id=${link.entity_id}::uuid`)[
              0
            ].content,
            "one\n\ntwo",
          );
          const count = metadataWrites;
          assertEquals((await runPage(memoPage)).result, "duplicate");
          assertEquals(metadataWrites, count);
          await sql.begin(async (tx) => {
            await tx`select set_config('diurna.sync_protocol','2',true)`;
            await tx`update public.memos set title='Local edit',revision=revision+1 where id=${link.entity_id}::uuid`;
          });
          assertEquals((await runPage(memoPage)).reason, "remote_create_echo");
          assertEquals(
            (await mapping(notion, memoPage)).last_synced_revision,
            link.last_synced_revision,
          );
          assertEquals(
            (await mapping(notion, memoPage)).inbound_state,
            "ready",
          );
          pages.get(memoPage)!.blocks = [paragraph("Remote changed too")];
          pages.get(memoPage)!.page.last_edited_time = "2026-09-10T00:05:00Z";
          assertEquals((await runPage(memoPage)).result, "conflict");
        },
      );

      await t.step(
        "Notion unsupported and incomplete drafts later retry; unrelated parent ignored",
        async () => {
          const unrelated = page(crypto.randomUUID());
          assertEquals((await runPage(unrelated)).reason, "unmanaged_parent");
          assertEquals(await mapping(notion, unrelated), undefined);
          const rich = page(memo, "Rich", [{ type: "heading_1" }]);
          assertEquals((await runPage(rich)).reason, "unsupported_content");
          assertEquals(await mapping(notion, rich), undefined);
          pages.get(rich)!.blocks = [paragraph("supported")];
          assertEquals((await runPage(rich)).result, "created");
          const draft = page(diary, "Draft", [paragraph("draft")]);
          assertEquals(
            (await runPage(draft)).reason,
            "missing_required_fields",
          );
          pages.get(draft)!.page.properties!.Date = {
            date: { start: "2026-09-10" },
          };
          assertEquals((await runPage(draft)).result, "created");
        },
      );

      await t.step(
        "Notion valid ID recovery, invalid metadata and foreign ID isolation",
        async () => {
          const original = page(memo, "Restore", [paragraph("content")]);
          await runPage(original);
          const before = await mapping(notion, original);
          await sql`delete from public.external_sync_links where id=${before.id}::uuid`;
          assertEquals((await runPage(original)).result, "recovered");
          assertEquals(
            (await mapping(notion, original)).entity_id,
            before.entity_id,
          );
          const foreign = crypto.randomUUID();
          await sql.begin(async (tx) => {
            await tx`select set_config('diurna.sync_protocol','2',true)`;
            await tx`insert into public.memos(id,user_id,title) values(${foreign}::uuid,${foreignUser}::uuid,'foreign')`;
          });
          for (const candidate of ["bad-id", foreign]) {
            const remote = page(memo, "Isolated");
            pages.get(remote)!.page.properties!["Diurna ID"] = {
              rich_text: [{ text: { content: candidate } }],
            };
            assertEquals((await runPage(remote)).result, "created");
            assert((await mapping(notion, remote)).entity_id !== candidate);
          }
        },
      );

      await t.step(
        "Notion failed metadata write is durable, repair discovers historical page",
        async () => {
          const failed = page(memo, "Retry");
          failMetadata = true;
          await assertRejects(
            () => runPage(failed),
            Error,
            "notion_metadata_503",
          );
          const before = await mapping(notion, failed);
          assert(before);
          assert(
            (await sql`select metadata_pending from integrations.remote_object_status where connection_id=${notion}::uuid and external_id=${failed}`)[
              0
            ].metadata_pending,
          );
          failMetadata = false;
          // Pending metadata must not block a later remote delete.
          const removed = page(memo, "Removed during metadata retry");
          failMetadata = true;
          await assertRejects(() => runPage(removed), Error, "notion_metadata_503");
          pages.get(removed)!.page.archived = true;
          assertEquals((await runPage(removed)).result, "remote_deleted");
          const removedLink = await mapping(notion, removed);
          assertEquals((await sql`select count(*) as n from public.memos where id=${removedLink.entity_id}::uuid`)[0].n, "1");
          failMetadata = false;
          const historical = page(inbox, "Old page");
          await repairNotionConnection({
            connectionId: notion,
            fetchImpl: notionFetch,
          });
          assert(await mapping(notion, historical));
          assertEquals(
            (await mapping(notion, failed)).entity_id,
            before.entity_id,
          );
          assertEquals(
            (await sql`select metadata_pending from integrations.remote_object_status where connection_id=${notion}::uuid and external_id=${failed}`)[
              0
            ].metadata_pending,
            false,
          );
          const boot = page(memo, "Bootstrap page");
          await sql`update public.integration_connections set inbound_status='bootstrapping' where id=${notion}::uuid`;
          assertEquals(
            (await bootstrapNotionConnection({
              connectionId: notion,
              fetchImpl: notionFetch,
            })).result,
            "ok",
          );
          assert(await mapping(notion, boot));
        },
      );

      await t.step(
        "Notion discovery resumes a bounded batch and preserves catch-up watermark",
        async () => {
          const remote = page(memo, "Paged history");
          await sql`delete from integrations.remote_discovery_state where connection_id=${notion}::uuid and source_id=${memo}`;
          let queries = 0;
          const fetchImpl = async (url: string, init?: RequestInit) => {
            if (url.includes("/data_sources/")) {
              const body = JSON.parse(String(init?.body));
              queries++;
              if (queries === 4) assertEquals(body.start_cursor, "cursor-3");
              return Response.json({
                results: [{ id: remote }],
                has_more: queries < 4,
                next_cursor: queries < 4 ? `cursor-${queries}` : null,
              });
            }
            return await notionFetch(url, init);
          };
          const args = {
            connectionId: notion,
            container: { memo_ds: memo },
            token: "fixture",
            fetchImpl,
          };
          assertEquals(await discoverNotionPages(args), false);
          const first = await mapping(notion, remote);
          assertEquals(await discoverNotionPages(args), true);
          assertEquals(queries, 4);
          assertEquals(
            (await mapping(notion, remote)).entity_id,
            first.entity_id,
          );
          const [connection] =
            await sql`select inbound_repair_state from public.integration_connections where id=${notion}::uuid`;
          assert(connection.inbound_repair_state[memo].sinceIso);
        },
      );

      await t.step(
        "owned Notion recovery preserves CRLF and freezes unsupported content",
        async () => {
          const remote = page(memo, "CRLF restore", [
            paragraph("one"),
            paragraph("two"),
          ]);
          await runPage(remote);
          const link = await mapping(notion, remote);
          await sql.begin(async (tx) => {
            await tx`select set_config('diurna.sync_protocol','2',true)`;
            await tx`update public.memos set content=${"one\r\ntwo"},revision=revision+1 where id=${link.entity_id}::uuid`;
            await tx`delete from public.external_sync_links where id=${link.id}::uuid`;
          });
          assertEquals((await runPage(remote)).result, "recovered");
          assertEquals(
            (await sql`select content from public.memos where id=${link.entity_id}::uuid`)[
              0
            ].content,
            "one\r\ntwo",
          );
          await sql`delete from public.external_sync_links where connection_id=${notion}::uuid and external_id=${remote}`;
          pages.get(remote)!.blocks = [{ type: "heading_1" }];
          assertEquals((await runPage(remote)).result, "conflict");
          assertEquals(
            (await mapping(notion, remote)).entity_id,
            link.entity_id,
          );
        },
      );

      await t.step(
        "connection processing lock serializes provider I/O",
        async () => {
          const events: string[] = [];
          let release!: () => void, entered!: () => void;
          const inLock = new Promise<void>((r) => entered = r),
            gate = new Promise<void>((r) => release = r);
          const inbound = withConnectionInboundLock(google, async () => {
            events.push("inbound");
            entered();
            await gate;
            events.push("inbound-done");
          });
          await inLock;
          const outbound = withConnectionInboundLock(google, async () => {
            events.push("outbound");
          });
          release();
          await Promise.all([inbound, outbound]);
          assertEquals(events, ["inbound", "inbound-done", "outbound"]);
        },
      );

      await t.step("disabled inbound never creates or recovers", async () => {
        await sql`update public.integration_connections set inbound_status='disabled' where id in (${google}::uuid,${notion}::uuid)`;
        assertEquals(
          (await runPage(page(memo, "Disabled"))).reason,
          "inbound_disabled",
        );
        assertEquals(
          (await reconcileExternalObject({
            connectionId: google,
            provider: "google",
            containerId: "managed",
            entityType: "calendar_events",
            externalId: "disabled",
            candidateId: null,
            patch: { title: "Disabled", event_date: "2026-09-10" },
            remoteSnapshot: {},
          })).reason,
          "inbound_disabled",
        );
      });
    } finally {
      await sql.begin(async (tx) => {
        await tx`select set_config('diurna.sync_protocol','2',true)`;
        // Delete entities while their users still exist: the production signal
        // trigger needs the user FK even during fixture cleanup.
        await tx`delete from public.inbox_items where user_id in (${user}::uuid,${foreignUser}::uuid)`;
        await tx`delete from public.memos where user_id in (${user}::uuid,${foreignUser}::uuid)`;
        await tx`delete from public.diary_entries where user_id in (${user}::uuid,${foreignUser}::uuid)`;
        await tx`delete from public.calendar_events where user_id in (${user}::uuid,${foreignUser}::uuid)`;
        await tx`delete from auth.users where id in (${user}::uuid,${foreignUser}::uuid)`;
      });
      await sql.end();
      if (previousUrl) Deno.env.set("SUPABASE_DB_URL", previousUrl);
      else Deno.env.delete("SUPABASE_DB_URL");
      if (previousKey) Deno.env.set("INTEGRATION_TOKEN_KEY", previousKey);
      else Deno.env.delete("INTEGRATION_TOKEN_KEY");
    }
  },
});
