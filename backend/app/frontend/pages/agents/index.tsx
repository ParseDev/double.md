import { Head, Link } from "@inertiajs/react"
import { ArrowUpRight, Bot, ChevronDown, ChevronRight, Filter, LayoutGrid, Network, Plus, Rocket, Search } from "lucide-react"
import { useMemo, useState } from "react"
import { toast } from "sonner"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

import { AgentBlob } from "@/components/agent-blob"
import { GlowCard, Overline, StatusDot } from "@/components/brand"
import { PageHeader } from "@/components/page-header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import AppLayout from "@/layouts/app-layout"
import { agentPath, dashboardPath, newAgentPath } from "@/routes"
import type { Agent } from "@/types"
import { TemplateDeployCard, type DeployTemplate } from "@/components/template-deploy-card"

const STATUS_MAP: Record<string, { dot: "online" | "working" | "idle" | "error" | "offline"; label: string }> = {
  running: { dot: "working", label: "Running" },
  pending: { dot: "idle", label: "Pending" },
  paused: { dot: "offline", label: "Paused" },
  stopped: { dot: "error", label: "Stopped" },
  starting: { dot: "working", label: "Starting" },
}

const FILTERS = ["All", "Running", "Paused", "Stopped"] as const
type FilterKey = (typeof FILTERS)[number]
type ViewMode = "cards" | "tree"

export default function AgentsIndex({ agents, templates = [] }: { agents: Agent[]; templates?: DeployTemplate[] }) {
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<FilterKey>("All")
  const [view, setView] = useState<ViewMode>("cards")
  const [rollConfirm, setRollConfirm] = useState(false)
  const [rolling, setRolling] = useState(false)

  const rollEngine = async () => {
    setRolling(true)
    const csrf = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ""
    try {
      const res = await fetch("/ops/roll_engine", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: "{}",
      })
      const data = await res.json()
      if (data.ok) toast.success(`Queued: ${agents.filter((a) => a.status === "running").length} agents will update (staggered 10s apart)`)
      else toast.error(`Roll failed: ${data.message}`)
    } catch (err) {
      toast.error(`Roll failed: ${(err as Error).message}`)
    } finally {
      setRolling(false)
      setRollConfirm(false)
    }
  }

  const filtered = useMemo(() => {
    let list = agents
    if (filter !== "All") {
      list = list.filter((a) => a.status.toLowerCase() === filter.toLowerCase())
    }
    if (search) {
      const q = search.toLowerCase()
      list = list.filter(
        (a) =>
          a.name.toLowerCase().includes(q) ||
          a.role.toLowerCase().includes(q),
      )
    }
    return list
  }, [agents, filter, search])

  const runningCount = agents.filter((a) => a.status === "running").length

  return (
    <AppLayout
      crumbs={[
        { label: "Workspace", href: dashboardPath() },
        { label: "Agents" },
      ]}
      topBarActions={
        <div className="flex items-center gap-1.5">
          {runningCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 hover:bg-muted hover:text-foreground"
              onClick={() => setRollConfirm(true)}
              disabled={rolling}
            >
              <Rocket className="size-3.5" />
              Roll engine
            </Button>
          )}
          <Button asChild size="sm" className="h-8 gap-1.5 font-semibold shadow-[0_0_0_1px_var(--color-indigo),0_6px_16px_-6px_var(--indigo-glow)]">
            <Link href={newAgentPath()}>
              <Plus className="size-3.5" strokeWidth={2.5} />
              New agent
            </Link>
          </Button>
        </div>
      }
    >
      <Head title="Agents" />

      <PageHeader
        eyebrow="Roster"
        title="Agents"
        description={`${agents.length} agent${agents.length === 1 ? "" : "s"} in your workspace · ${runningCount} running right now.`}
      />

      {agents.length > 0 && (
        <div className="mb-6 flex flex-wrap items-center gap-3">
          {view === "cards" && (
            <>
              <div className="relative flex-1 min-w-[240px] max-w-md">
                <Search className="pointer-events-none absolute left-3 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
                <Input
                  placeholder="Search by name or role…"
                  className="h-9 pl-9"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>

              <div className="flex items-center gap-1 rounded-md border bg-card p-1">
                <Filter className="ml-2 size-3 text-muted-foreground" />
                {FILTERS.map((f) => (
                  <button
                    key={f}
                    onClick={() => setFilter(f)}
                    className={`rounded-sm px-2.5 py-1 text-[11px] font-medium transition-colors ${
                      filter === f
                        ? "bg-[var(--indigo-surface)] text-[var(--color-indigo)]"
                        : "text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {f}
                  </button>
                ))}
              </div>
            </>
          )}

          <div className="flex items-center gap-1 rounded-md border bg-card p-1">
            <button
              onClick={() => setView("cards")}
              title="Card view"
              className={`flex items-center gap-1.5 rounded-sm px-2 py-1 text-[11px] font-medium transition-colors ${
                view === "cards"
                  ? "bg-[var(--indigo-surface)] text-[var(--color-indigo)]"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <LayoutGrid className="size-3" />
              Cards
            </button>
            <button
              onClick={() => setView("tree")}
              title="Org chart"
              className={`flex items-center gap-1.5 rounded-sm px-2 py-1 text-[11px] font-medium transition-colors ${
                view === "tree"
                  ? "bg-[var(--indigo-surface)] text-[var(--color-indigo)]"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <Network className="size-3" />
              Tree
            </button>
          </div>

          <span className="ml-auto font-mono text-[11px] text-muted-foreground">
            {view === "cards" ? `${filtered.length} shown` : `${agents.length} total`}
          </span>
        </div>
      )}

      {agents.length === 0 ? (
        <EmptyState templates={templates} />
      ) : view === "tree" ? (
        <AgentTree agents={agents} />
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-20 text-center">
          <p className="font-mono text-sm text-muted-foreground">No matches</p>
          <p className="text-sm text-muted-foreground">
            No agents match your search. Try a different keyword or filter.
          </p>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((agent) => (
            <AgentListCard key={agent.id} agent={agent} />
          ))}
        </div>
      )}

      <Dialog open={rollConfirm} onOpenChange={(open) => !open && setRollConfirm(false)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Rocket className="size-5" />
              Roll every agent to latest engine
            </DialogTitle>
            <DialogDescription className="pt-2">
              Updates each running agent to <span className="font-mono">ghcr.io/parsedev/alchemy-engine:latest</span> (the most recent CI build).
            </DialogDescription>
          </DialogHeader>
          <ul className="space-y-2 text-sm">
            <li className="text-muted-foreground flex gap-2">
              <span className="text-foreground">•</span>
              <span>{runningCount} agent{runningCount === 1 ? "" : "s"} will be updated, staggered 10s apart so they don't all blip at once.</span>
            </li>
            <li className="text-muted-foreground flex gap-2">
              <span className="text-foreground">•</span>
              <span>Each agent has ~20-40s of downtime while its Machine swaps to the new image. /data volume is preserved.</span>
            </li>
            <li className="text-muted-foreground flex gap-2">
              <span className="text-foreground">•</span>
              <span>In-flight chats may need a refresh to reconnect. Session transcripts survive.</span>
            </li>
          </ul>
          <div className="mt-2 flex items-center gap-2 rounded-md border border-amber-500/30 bg-amber-500/5 px-3 py-2 text-sm text-amber-700 dark:text-amber-400">
            <Rocket className="size-4" />
            <span className="font-medium">Estimated total:</span>
            <span>~{Math.ceil(runningCount * 10 / 60)} min for the fleet (10s stagger + 30s per agent)</span>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setRollConfirm(false)} disabled={rolling}>
              Cancel
            </Button>
            <Button onClick={rollEngine} disabled={rolling}>
              {rolling ? "Queueing…" : "Roll all now"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AppLayout>
  )
}

/* ---------- machine health ---------- */
// Derive a live health state from the Instance row. The engine pings
// /api/agent_instances/ready on boot and on its periodic heartbeat, so
// a fresh health_checked_at means the Machine is alive.
function machineHealth(agent: Agent): { tone: "ok" | "warn" | "bad" | "idle"; label: string; hint: string } {
  const inst = agent.instance
  if (!inst) return { tone: "idle", label: "No machine", hint: "Agent hasn't been provisioned yet" }
  if (inst.provisioning_error) return { tone: "bad", label: "Error", hint: inst.provisioning_error }

  const hb = inst.health_checked_at ? new Date(inst.health_checked_at) : null
  const ageMs = hb ? Date.now() - hb.getTime() : Infinity
  const ageMin = Math.floor(ageMs / 60_000)

  if (inst.status !== "running") {
    return { tone: "idle", label: inst.status ?? "Stopped", hint: `Last heartbeat: ${hb ? `${ageMin}m ago` : "never"}` }
  }
  if (ageMin < 2) return { tone: "ok",   label: "Healthy", hint: `Heartbeat ${ageMin === 0 ? "just now" : `${ageMin}m ago`}` }
  if (ageMin < 10) return { tone: "warn", label: `Stale ${ageMin}m`, hint: "Engine hasn't reported a heartbeat recently" }
  return { tone: "bad", label: "Silent", hint: hb ? `Last heartbeat ${ageMin}m ago — Machine may be stopped` : "No heartbeat yet" }
}

/* ---------- card ---------- */
function AgentListCard({ agent }: { agent: Agent }) {
  const st = STATUS_MAP[agent.status] ?? STATUS_MAP.stopped
  const preview = agent.instructions_md ?? agent.identity_md ?? null
  const health = machineHealth(agent)
  const healthColor =
    health.tone === "ok"   ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400" :
    health.tone === "warn" ? "border-amber-500/40  bg-amber-500/10  text-amber-700  dark:text-amber-400" :
    health.tone === "bad"  ? "border-destructive/40 bg-destructive/10 text-destructive" :
                             "border-muted-foreground/20 bg-muted text-muted-foreground"

  return (
    <Link href={agentPath(agent.id)} className="group block">
      <GlowCard
        glow={agent.status === "running" ? "soft" : "none"}
        tint="cyan"
        className="h-full min-h-[192px] p-5"
      >
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="relative">
              <AgentBlob name={agent.name} size={40} />
              <span className="absolute bottom-0.5 right-0.5">
                <StatusDot status={st.dot} pulse={agent.status === "running"} ring />
              </span>
            </div>
            <div className="min-w-0">
              <h3 className="truncate font-display text-[15px] font-semibold leading-tight tracking-[-0.015em] text-foreground">
                {agent.name}
              </h3>
              <p className="mt-0.5 text-xs text-muted-foreground">{agent.role}</p>
            </div>
          </div>
          <div className="flex items-center gap-1.5">
            <span
              className={`rounded-sm border px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-[0.08em] ${healthColor}`}
              title={health.hint}
            >
              {health.label}
            </span>
            <span className="rounded-sm border px-2 py-0.5 font-mono text-[10px] uppercase tracking-[0.1em] text-muted-foreground">
              {st.label}
            </span>
          </div>
        </div>

        <div className="mt-4 min-h-[48px]">
          {preview ? (
            <p className="line-clamp-3 text-[13px] leading-relaxed text-muted-foreground">
              {preview}
            </p>
          ) : (
            <p className="text-[13px] italic text-muted-foreground/60">
              No instructions set yet
            </p>
          )}
        </div>

        <div className="mt-5 flex items-center justify-between border-t pt-3">
          <div className="flex items-center gap-2">
            {agent.ai_config && (
              <span className="rounded-sm bg-[var(--muted)] px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground">
                {agent.ai_config.model_id}
              </span>
            )}
            {agent.manager && (
              <span className="font-mono text-[10px] text-muted-foreground">
                → {agent.manager.name}
              </span>
            )}
          </div>
          <ArrowUpRight className="size-3.5 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
        </div>
      </GlowCard>
    </Link>
  )
}

/* ---------- tree ---------- */
type TreeNode = { agent: Agent; children: TreeNode[] }

function buildTree(agents: Agent[]): TreeNode[] {
  const byId = new Map<string, TreeNode>()
  agents.forEach((a) => byId.set(a.id, { agent: a, children: [] }))

  const roots: TreeNode[] = []
  agents.forEach((a) => {
    const node = byId.get(a.id)!
    const managerId = a.manager?.id
    const parent = managerId ? byId.get(managerId) : undefined
    if (parent) parent.children.push(node)
    else roots.push(node)
  })

  const sortRec = (nodes: TreeNode[]) => {
    nodes.sort((x, y) => x.agent.name.localeCompare(y.agent.name))
    nodes.forEach((n) => sortRec(n.children))
  }
  sortRec(roots)
  return roots
}

function AgentTree({ agents }: { agents: Agent[] }) {
  const roots = useMemo(() => buildTree(agents), [agents])

  if (roots.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 py-20 text-center">
        <p className="font-mono text-sm text-muted-foreground">No roots</p>
        <p className="text-sm text-muted-foreground">
          Every agent has a manager — at least one needs to be a root for the tree to render.
        </p>
      </div>
    )
  }

  return (
    <GlowCard tint="cyan" className="p-5">
      <ul className="space-y-1">
        {roots.map((node) => (
          <TreeRow key={node.agent.id} node={node} depth={0} />
        ))}
      </ul>
    </GlowCard>
  )
}

function TreeRow({ node, depth }: { node: TreeNode; depth: number }) {
  const [open, setOpen] = useState(true)
  const hasChildren = node.children.length > 0
  const { agent } = node
  const st = STATUS_MAP[agent.status] ?? STATUS_MAP.stopped

  return (
    <li>
      <div
        className="group flex items-center gap-2 rounded-md py-1.5 pr-2 hover:bg-muted/50"
        style={{ paddingLeft: `${depth * 20 + 4}px` }}
      >
        <button
          type="button"
          onClick={() => hasChildren && setOpen((o) => !o)}
          className={`flex size-5 shrink-0 items-center justify-center rounded-sm ${
            hasChildren ? "text-muted-foreground hover:bg-muted hover:text-foreground" : "invisible"
          }`}
          aria-label={open ? "Collapse" : "Expand"}
        >
          {open ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
        </button>

        <span className="flex size-6 shrink-0 items-center justify-center">
          <StatusDot status={st.dot} pulse={agent.status === "running"} />
        </span>

        <Link
          href={agentPath(agent.id)}
          className="flex min-w-0 flex-1 items-center gap-2"
        >
          <span className="truncate font-display text-sm font-semibold text-foreground group-hover:text-[var(--color-indigo)]">
            {agent.name}
          </span>
          <span className="truncate text-xs text-muted-foreground">{agent.role}</span>
          {hasChildren && (
            <span className="rounded-sm border px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground">
              {node.children.length} report{node.children.length === 1 ? "" : "s"}
            </span>
          )}
        </Link>

        {agent.ai_config && (
          <span className="hidden rounded-sm bg-[var(--muted)] px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:inline">
            {agent.ai_config.model_id}
          </span>
        )}
        <span className="rounded-sm border px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-[0.08em] text-muted-foreground">
          {st.label}
        </span>
      </div>

      {hasChildren && open && (
        <ul className="space-y-1">
          {node.children.map((child) => (
            <TreeRow key={child.agent.id} node={child} depth={depth + 1} />
          ))}
        </ul>
      )}
    </li>
  )
}

/* ---------- empty ---------- */
// No agents yet: lead with a gallery of deployable templates (one click into
// the new-agent workflow) and keep "start from scratch" as a secondary path —
// rather than dropping the user straight into the create form.
function EmptyState({ templates }: { templates: DeployTemplate[] }) {
  return (
    <GlowCard glow="soft" tint="indigo" className="px-6 py-12">
      <div className="text-center">
        <div className="mx-auto flex size-12 items-center justify-center rounded-md border border-dashed">
          <Bot className="size-5 text-muted-foreground" />
        </div>
        <Overline className="mt-5 justify-center">Workspace empty</Overline>
        <h3 className="mx-auto mt-3 max-w-sm font-display text-xl font-semibold tracking-[-0.02em] text-foreground">
          Hire your first AI teammate.
        </h3>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
          {templates.length > 0
            ? "Deploy a ready-made template below, or start from a blank agent and write the role yourself."
            : "Give them a role, connect the tools they'll use, set an approval policy. They start working on a schedule of your choosing."}
        </p>
      </div>

      {templates.length > 0 && (
        <div className="mx-auto mt-8 grid max-w-4xl grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {templates.map((t) => (
            <TemplateDeployCard key={t.slug} t={t} />
          ))}
        </div>
      )}

      <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
        <Button asChild className="gap-1.5">
          <Link href={newAgentPath()}>
            <Plus className="size-3.5" />
            Create new agent
          </Link>
        </Button>
        {templates.length > 0 && (
          <Button asChild variant="outline" className="gap-1.5">
            <a href="/templates">
              Browse all templates
              <ArrowUpRight className="size-3.5" />
            </a>
          </Button>
        )}
      </div>
    </GlowCard>
  )
}
