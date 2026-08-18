import { Link, usePage } from "@inertiajs/react"
import { AgentBlob } from "@/components/agent-blob"
import { useState } from "react"
import {
  Plug,
  Plus,
  Sun,
  Moon,
  PanelLeftClose,
  PanelLeft,
  ChevronRight,
  CornerDownRight,
  AlertCircle,
} from "lucide-react"

import AppLogo from "@/components/app-logo"
import { NavUser } from "@/components/nav-user"
import { useTheme } from "@/hooks/use-theme"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  useSidebar,
} from "@/components/ui/sidebar"
import {
  dashboardPath,
  agentsPath,
  integrationsPath,
  newAgentPath,
} from "@/routes"

interface AgentNode {
  id: string
  name: string
  slug: string
  role: string
  status: string
  depth: number
  has_children: boolean
  pending_approvals: number
  oldest_pending_age_hours: number | null
  active_conversations: number
}

interface SharedProps {
  [key: string]: unknown
  is_platform_admin?: boolean
  agents_tree?: AgentNode[] | null
}

export function AppSidebar() {
  const { theme, setTheme } = useTheme()
  const { toggleSidebar, open } = useSidebar()
  const { props, url } = usePage<SharedProps>()
  const agents = props.agents_tree || []

  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton asChild>
              <Link href={dashboardPath()} prefetch>
                <AppLogo />
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup className="!pt-6 !pb-2">
          <SidebarGroupContent>
            <Link
              href={newAgentPath()}
              className="group relative flex h-9 w-full items-center gap-2 overflow-hidden rounded-md bg-[var(--color-indigo)] px-3 text-[13px] font-semibold text-white shadow-[0_0_0_1px_rgba(255,255,255,0.05),0_8px_20px_-8px_var(--indigo-glow)] transition-all hover:-translate-y-0.5 hover:bg-[var(--color-indigo-600)] hover:shadow-[0_0_0_1px_rgba(255,255,255,0.08),0_12px_28px_-8px_var(--indigo-glow)]"
            >
              <span
                aria-hidden
                className="pointer-events-none absolute inset-0 -translate-x-full bg-gradient-to-r from-transparent via-white/25 to-transparent transition-transform duration-700 ease-out group-hover:translate-x-full"
              />
              <Plus className="relative size-3.5" strokeWidth={2.5} />
              <span className="relative">New agent</span>
            </Link>
          </SidebarGroupContent>
        </SidebarGroup>

        {/* Agents tree — the main focus of the sidebar. Sub-agents nest under
            their manager with a connector glyph. Each leaf shows pending +
            inbox counts when non-zero. */}
        <SidebarGroup>
          <SidebarGroupLabel className="flex items-center justify-between pr-2">
            <span>Agents</span>
            <Link
              href={agentsPath()}
              className="rounded px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-sidebar-accent hover:text-foreground"
              title="View all agents"
            >
              All
            </Link>
          </SidebarGroupLabel>
          <SidebarGroupContent>
            {agents.length === 0 ? (
              <p className="px-2 py-3 text-[11px] text-muted-foreground">No agents yet. Hit + New agent.</p>
            ) : (
              <AgentTree nodes={agents} currentUrl={url} />
            )}
          </SidebarGroupContent>
        </SidebarGroup>

        {/* Everything that is not an agent lives in the user menu now. The
            one exception is Integrations: connecting a tool is part of getting
            an agent working, so it stays one click from the roster. */}
        <SidebarGroup className="mt-auto">
          <SidebarGroupContent>
            <SidebarLink href={integrationsPath()} icon={Plug} label="Plugins" current={url} />
          </SidebarGroupContent>
        </SidebarGroup>

      </SidebarContent>

      <SidebarFooter>
        <SidebarGroup className="p-0">
          <SidebarGroupContent className="flex items-center gap-1 px-1">
            <button
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              className="flex flex-1 items-center gap-2 rounded-md px-2.5 py-1.5 text-[11px] font-mono uppercase tracking-[0.14em] text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground"
            >
              {theme === "dark" ? <Sun className="size-3.5" /> : <Moon className="size-3.5" />}
              <span>{theme === "dark" ? "Light" : "Dark"}</span>
            </button>
            <button
              onClick={toggleSidebar}
              className="flex size-7 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground"
              title={open ? "Collapse sidebar" : "Expand sidebar"}
            >
              {open ? <PanelLeftClose className="size-3.5" /> : <PanelLeft className="size-3.5" />}
            </button>
          </SidebarGroupContent>
        </SidebarGroup>
        <NavUser />
      </SidebarFooter>
    </Sidebar>
  )
}

// ── Agent tree ────────────────────────────────────────────────────────

const AGENT_EXPAND_PREFIX = "sidebar.agent."
const AGENT_EXPAND_SUFFIX = ".open"

function readAgentExpanded(id: string, def: boolean): boolean {
  if (typeof window === "undefined") return def
  const raw = window.localStorage.getItem(`${AGENT_EXPAND_PREFIX}${id}${AGENT_EXPAND_SUFFIX}`)
  return raw == null ? def : raw === "1"
}

function AgentTree({ nodes, currentUrl }: { nodes: AgentNode[]; currentUrl: string }) {
  // Build the parent chain per row so we can hide rows whose ancestor is
  // collapsed. The backend emits depth-walked order, so the parent of each
  // row is the most recent prior row with depth-1.
  const ancestorIds: string[][] = []
  const stack: AgentNode[] = []
  for (const n of nodes) {
    while (stack.length > 0 && stack[stack.length - 1].depth >= n.depth) stack.pop()
    ancestorIds.push(stack.map((a) => a.id))
    stack.push(n)
  }

  // Track expanded state for every manager agent (anyone with has_children).
  // Default: open. Persists per browser via localStorage.
  const managerIds = nodes.filter((n) => n.has_children).map((n) => n.id)
  const [expandMap, setExpandMap] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {}
    for (const id of managerIds) init[id] = readAgentExpanded(id, true)
    return init
  })

  function toggle(id: string) {
    setExpandMap((prev) => {
      const next = { ...prev, [id]: !prev[id] }
      if (typeof window !== "undefined") {
        window.localStorage.setItem(
          `${AGENT_EXPAND_PREFIX}${id}${AGENT_EXPAND_SUFFIX}`,
          next[id] ? "1" : "0",
        )
      }
      return next
    })
  }

  return (
    <div className="space-y-0.5">
      {nodes.map((node, idx) => {
        // Hidden when any ancestor is collapsed.
        const hidden = ancestorIds[idx].some((aid) => expandMap[aid] === false)
        if (hidden) return null
        return (
          <AgentRow
            key={node.id}
            node={node}
            currentUrl={currentUrl}
            expanded={expandMap[node.id] !== false}
            onToggle={() => toggle(node.id)}
          />
        )
      })}
    </div>
  )
}

function AgentRow({
  node,
  currentUrl,
  expanded,
  onToggle,
}: {
  node: AgentNode
  currentUrl: string
  expanded: boolean
  onToggle: () => void
}) {
  const href = `/agents/${node.id}`
  const active = currentUrl === href || currentUrl.startsWith(`${href}/`) || currentUrl.startsWith(`${href}?`)
  return (
    <div
      className={`group flex items-center gap-1 rounded-md transition-colors ${
        active ? "bg-sidebar-accent text-foreground" : "text-foreground/85 hover:bg-sidebar-accent/60"
      }`}
      style={{ paddingLeft: `${node.depth * 0.75 + 0.25}rem` }}
    >
      {node.has_children ? (
        <button
          type="button"
          onClick={(e) => { e.preventDefault(); onToggle() }}
          className="flex size-4 shrink-0 items-center justify-center rounded text-muted-foreground hover:text-foreground"
          aria-label={expanded ? "Collapse" : "Expand"}
        >
          <ChevronRight className={`size-3 transition-transform ${expanded ? "rotate-90" : ""}`} />
        </button>
      ) : node.depth > 0 ? (
        <CornerDownRight className="size-3 shrink-0 text-muted-foreground/50" />
      ) : (
        <span className="inline-block size-3 shrink-0" />
      )}
      <Link href={href} className="flex min-w-0 flex-1 items-center gap-1.5 py-1 pr-2 text-[12.5px]" prefetch>
        <AgentBlob name={node.name} size={18} animate={false} className="shrink-0" />
        <span className="min-w-0 flex-1 truncate font-medium">{node.name}</span>
        {node.status === "running" && (
          <span className="size-1.5 shrink-0 rounded-full bg-emerald-500" title="Running" />
        )}
        {node.pending_approvals > 0 && (() => {
          // Color shifts with age — fresh stays amber, >3d brightens, >7d
          // turns red so stuck approvals are visually loud.
          const ageH = node.oldest_pending_age_hours ?? 0
          const tone =
            ageH >= 24 * 7 ? "bg-red-500/15 text-red-600 dark:text-red-400" :
            ageH >= 24 * 3 ? "bg-orange-500/15 text-orange-600 dark:text-orange-400" :
                             "bg-amber-500/15 text-amber-600 dark:text-amber-400"
          const ageLabel = ageH >= 24 ? `${Math.floor(ageH / 24)}d` : `${Math.max(1, ageH)}h`
          return (
            <span
              className={`inline-flex shrink-0 items-center gap-0.5 rounded-full px-1.5 py-px text-[9px] font-semibold tabular-nums ${tone}`}
              title={`${node.pending_approvals} approval${node.pending_approvals === 1 ? "" : "s"} pending — oldest is ${ageLabel} old`}
            >
              <AlertCircle className="size-2.5" />
              {node.pending_approvals}
            </span>
          )
        })()}
      </Link>
    </div>
  )
}

// ── Collapsible group ───────────────────────────────────────────────

function SidebarLink({
  href,
  icon: Icon,
  label,
  current,
  indent = false,
}: {
  href: string
  icon: typeof Plug
  label: string
  current: string
  indent?: boolean
}) {
  const active = current === href || current.startsWith(`${href}/`) || current.startsWith(`${href}?`)
  return (
    <Link
      href={href}
      className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-[12.5px] font-medium transition-colors ${
        indent ? "ml-3.5" : ""
      } ${active ? "bg-sidebar-accent text-foreground" : "text-foreground/85 hover:bg-sidebar-accent/60"}`}
      prefetch
    >
      <Icon className={`size-3.5 ${active ? "text-foreground" : "text-muted-foreground"}`} />
      <span>{label}</span>
    </Link>
  )
}
