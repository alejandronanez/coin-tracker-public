type AnyEvent = { type: string; properties: Record<string, unknown> }
type Ctx = { $: unknown; client: any; worktree?: string; directory: string }

const MAX_RETRIES = 3
const FAST_CHECKS = "mix format --check-formatted && mix compile --warning-as-errors"
const edited = new Set<string>()
const retries = new Map<string, number>()

export const VerifyOnIdle = async (ctx: Ctx) => {
  const $ = ctx.$ as any
  const client = ctx.client
  const worktree = ctx.worktree ?? ctx.directory

  return {
    event: async ({ event }: { event: AnyEvent }) => {
      try {
        const t = event.type
        const p = event.properties

        if (t === "session.diff") {
          const sid = p.sessionID as string | undefined
          if (sid) edited.add(sid)
          return
        }
        if (t === "session.deleted") {
          const info = p.info as { id: string } | undefined
          if (info?.id) {
            edited.delete(info.id)
            retries.delete(info.id)
          }
          return
        }
        if (t !== "session.idle") return

        const sid = p.sessionID as string | undefined
        if (!sid || !edited.has(sid)) return
        edited.delete(sid)

        const attempt = retries.get(sid) ?? 0
        if (attempt >= MAX_RETRIES) {
          retries.delete(sid)
          await client.tui
            .showToast({
              body: {
                message: `verify-on-idle: fast checks failed ${MAX_RETRIES}x — needs human review`,
                variant: "warning",
              },
            })
            .catch(() => {})
          return
        }

        const result = await runChecks($, worktree)
        if (result.ok) {
          retries.delete(sid)
          return
        }

        retries.set(sid, attempt + 1)
        const clipped =
          result.output.length > 4000
            ? result.output.slice(0, 4000) + "\n...(truncated)"
            : result.output
        const text =
          `Verification failed (attempt ${attempt + 1}/${MAX_RETRIES}). ` +
          `Fast checks (${FAST_CHECKS}) reported:\n\n${clipped}\n\n` +
          `Fix these issues. Do not claim done until checks pass.`

        queueMicrotask(() => {
          client
            .session.prompt({
              path: { id: sid },
              body: { parts: [{ type: "text", text }] },
            })
            .catch((err: unknown) =>
              client.app
                .log({
                  body: {
                    service: "verify-on-idle",
                    level: "error",
                    message: "re-prompt failed: " + String(err),
                  },
                })
                .catch(() => {})
            )
        })
      } catch (err) {
        await client.app
          .log({
            body: {
              service: "verify-on-idle",
              level: "error",
              message: "handler error: " + String(err),
            },
          })
          .catch(() => {})
      }
    },
  }
}

async function runChecks($: any, worktree: string): Promise<{ ok: boolean; output: string }> {
  try {
    await $`cd ${worktree} && MIX_ENV=test mix format --check-formatted`
  } catch (e: any) {
    return { ok: false, output: "[mix format --check-formatted]\n" + collect(e) }
  }
  try {
    await $`cd ${worktree} && MIX_ENV=test mix compile --warning-as-errors`
  } catch (e: any) {
    return { ok: false, output: "[mix compile --warning-as-errors]\n" + collect(e) }
  }
  return { ok: true, output: "" }
}

function collect(e: any): string {
  return [String(e?.stdout ?? ""), String(e?.stderr ?? ""), e?.message ? String(e.message) : ""]
    .filter(Boolean)
    .join("\n")
}
