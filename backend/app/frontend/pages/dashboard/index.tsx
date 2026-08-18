import { Head, Link, usePage } from "@inertiajs/react"
import { Plus } from "lucide-react"
import type { ComponentProps } from "react"

import { AgentBlob } from "@/components/agent-blob"
import { AgentChat } from "@/components/agent-chat"
import { StatusDot } from "@/components/brand"
import { Button } from "@/components/ui/button"
import AppLayout from "@/layouts/app-layout"
import { agentPath, newAgentPath } from "@/routes"
import type { User } from "@/types"

// Inertia's PageProps wants an index signature, which the shared SharedProps
// type does not carry. Declaring the slice this page reads keeps usePage typed
// without widening the shared type for everyone.
interface PageProps {
  [key: string]: unknown
  auth?: { user?: User | null }
}

interface ChatAgent {
  id: string
  name: string
  slug: string
  role: string
  status: string
  instance_status?: string | null
}

interface Props {
  /** Null only when the workspace has no agents at all. */
  agent: ChatAgent | null
  chat_messages?: ComponentProps<typeof AgentChat>["initialMessages"]
  agent_thinking?: ComponentProps<typeof AgentChat>["agentThinking"]
  live_tool_steps?: ComponentProps<typeof AgentChat>["liveToolSteps"]
  approvals_by_message?: ComponentProps<typeof AgentChat>["approvalsByMessage"]
  pending_action_approvals?: ComponentProps<typeof AgentChat>["pendingActionApprovals"]
}

// A freshly created agent reports `stopped` while its machine is still coming
// up, which reads as broken. Mirrors the same rule on the agent detail page.
function effectiveStatus(agent: ChatAgent): string {
  if (agent.status === "running" || !agent.instance_status) return agent.status
  const booting = ["provisioning", "starting", "pending", "running"].includes(agent.instance_status)
  return agent.status === "stopped" && booting ? "starting" : agent.status
}

function statusDot(status: string): "online" | "working" | "idle" | "error" | "offline" {
  if (status === "running" || status === "starting") return "working"
  if (status === "sleeping") return "idle"
  if (status === "paused") return "offline"
  return status === "stopped" ? "error" : "idle"
}

export default function DashboardIndex({
  agent,
  chat_messages = [],
  agent_thinking = null,
  live_tool_steps = [],
  approvals_by_message = {},
  pending_action_approvals = [],
}: Props) {
  const { auth } = usePage<PageProps>().props
  const currentUser = auth?.user ?? null

  if (!agent) return <EmptyWorkspace />

  const status = effectiveStatus(agent)

  return (
    <AppLayout
      fullBleed
      header={
        <div className="flex h-14 shrink-0 items-center gap-3 border-b px-4">
          <AgentBlob name={agent.name} size={26} animate={false} className="shrink-0" />
          <Link
            href={agentPath(agent.id)}
            className="min-w-0 truncate font-display text-[15px] font-semibold tracking-[-0.015em] text-foreground hover:underline"
          >
            {agent.name}
          </Link>
          <span className="flex shrink-0 items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.12em] text-muted-foreground">
            <StatusDot status={statusDot(status)} pulse={status !== "paused"} />
            {status}
          </span>
          <Button asChild size="sm" variant="outline" className="ml-auto h-8 shrink-0">
            <Link href={agentPath(agent.id)}>Open agent</Link>
          </Button>
        </div>
      }
    >
      <Head title={agent.name} />
      {/* The agent list is the sidebar; this is the other half of that split. */}
      <div className="flex-1 overflow-hidden">
        <AgentChat
          agentId={agent.id}
          agentName={agent.name}
          agentStatus={status}
          currentUser={currentUser}
          initialMessages={chat_messages}
          agentThinking={agent_thinking}
          liveToolSteps={live_tool_steps}
          approvalsByMessage={approvals_by_message}
          pendingActionApprovals={pending_action_approvals}
        />
      </div>
    </AppLayout>
  )
}

function EmptyWorkspace() {
  return (
    <AppLayout>
      <Head title="Sentrel" />
      <div className="flex flex-1 flex-col items-center justify-center gap-5 px-6 text-center">
        <AgentBlob name="Sentrel" size={96} animate="always" />
        <div>
          <h1 className="font-display text-2xl font-semibold tracking-[-0.02em] text-foreground">
            No agents yet
          </h1>
          <p className="mt-2 max-w-sm text-sm text-muted-foreground">
            Hire your first teammate and this page becomes the conversation with them.
          </p>
        </div>
        <Button asChild size="lg" className="gap-1.5">
          <Link href={newAgentPath()}>
            <Plus className="size-4" />
            New agent
          </Link>
        </Button>
      </div>
    </AppLayout>
  )
}
