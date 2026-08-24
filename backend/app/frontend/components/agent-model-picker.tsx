import { useState } from "react"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Brain, Check, Loader2, Search } from "lucide-react"
import { toast } from "sonner"
import { router } from "@inertiajs/react"
import { filterModels, useModelCatalog, type CatalogGroup, type CatalogOption } from "@/lib/model-catalog"

// Providers whose models are unusable without a BYO key in /settings/credentials.
// "anthropic" stays out of this gate: the platform ships an org-level fallback
// ANTHROPIC_API_KEY so Claude-direct models work even without a user key.
const KEY_REQUIRED_PROVIDERS = new Set(["openrouter"])

// Last-resort fallback list, used only when /model_catalog can't be reached
// (and parsed server-side by ModelCatalog for the same reason). The live list
// comes from catalog_models, synced daily from models.dev — add models there,
// not here.
const MODELS: Array<{
  group: string
  options: Array<{ provider: string; model_id: string; label: string; hint?: string }>
}> = [
  {
    group: "Anthropic (direct)",
    options: [
      { provider: "anthropic", model_id: "claude-opus-5",     label: "Claude Opus 5",     hint: "newest flagship — strongest overall" },
      { provider: "anthropic", model_id: "claude-sonnet-5",   label: "Claude Sonnet 5",   hint: "recommended default — fast + smart" },
      { provider: "anthropic", model_id: "claude-fable-5",    label: "Claude Fable 5",    hint: "long-form + creative" },
      { provider: "anthropic", model_id: "claude-opus-4-8",   label: "Claude Opus 4.8",   hint: "previous Opus" },
      { provider: "anthropic", model_id: "claude-haiku-4-5",  label: "Claude Haiku 4.5",  hint: "fastest + cheapest" },
    ],
  },
  // Subscription auth (anthropic_account / openai_account) — temporarily
  // hidden from the picker. Backend routing in agent_provisioner stays in
  // place; flip these back on once the OAuth flow is registered.
  {
    // Non-Anthropic OR models resolve via ANTHROPIC_DEFAULT_*_MODEL env vars
    // (set by Rails agent_provisioner) — the engine doesn't pass the slug to
    // the SDK directly, so client-side validation is bypassed.
    group: "OpenRouter — recommended",
    options: [
      { provider: "openrouter", model_id: "openai/gpt-5.6-terra-pro", label: "GPT-5.6 Terra Pro", hint: "OpenAI flagship" },
      { provider: "openrouter", model_id: "google/gemini-3.6-flash",  label: "Gemini 3.6 Flash",  hint: "fast + huge context" },
      { provider: "openrouter", model_id: "moonshotai/kimi-k3",       label: "Kimi K3",           hint: "top agentic tool use" },
      { provider: "openrouter", model_id: "x-ai/grok-4.5",            label: "Grok 4.5",          hint: "xAI flagship" },
      { provider: "openrouter", model_id: "z-ai/glm-5.2",            label: "GLM 5.2 (Z.ai)",    hint: "strong agentic coding" },
      { provider: "openrouter", model_id: "qwen/qwen3.7-plus",        label: "Qwen3.7 Plus",      hint: "open reasoning generalist" },
      { provider: "openrouter", model_id: "minimax/minimax-m3",       label: "MiniMax M3",        hint: "long-context reasoning" },
      { provider: "openrouter", model_id: "deepseek/deepseek-v4-pro", label: "DeepSeek V4 Pro",   hint: "strong reasoning, cheap" },
    ],
  },
]

interface Props {
  agentId: number
  currentProvider?: string | null
  currentModelId?: string | null
  // When true, shows the "via your Claude subscription" group at the top.
  // Set by the agent edit page only when the org has an active anthropic
  // OauthCredential — otherwise the option would 401 the moment it ran.
  anthropicAccountConnected?: boolean
  // LLM providers (e.g. ["openrouter", "openai"]) the org has BYO keys
  // stored for. Used to grey out rows whose key is missing — without a key,
  // the agent would 401 the moment it picked the model up.
  availableLlmProviders?: string[]
}

export function AgentModelPicker({ agentId, currentProvider, currentModelId, anthropicAccountConnected, availableLlmProviders = [] }: Props) {
  const [busy, setBusy] = useState(false)
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState("")
  // Loads the first time the dropdown opens, then cached for the tab.
  const { catalog, loading } = useModelCatalog(open)

  const subscriptionGroup = anthropicAccountConnected
    ? [{
        group: "Your Claude subscription",
        options: MODELS[0].options.map((m) => ({
          ...m,
          provider: "anthropic_account",
          hint: "via your Pro/Max subscription",
        })),
      }]
    : []
  // The server already drops / promotes the subscription group per org, so
  // when the live catalog is in hand it's authoritative.
  const groupedModels: CatalogGroup[] = catalog?.groups?.length
    ? catalog.groups
    : [...subscriptionGroup, ...MODELS]

  const searching = query.trim().length > 0
  const searchResults = searching
    ? filterModels(catalog?.all ?? groupedModels.flatMap((g) => g.options), query).slice(0, 60)
    : []

  const apply = async (provider: string, model_id: string) => {
    if (provider === currentProvider && model_id === currentModelId) return
    setBusy(true)
    const csrf = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ""
    try {
      const res = await fetch(`/agents/${agentId}/ai_config`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf, Accept: "application/json" },
        body: JSON.stringify({ ai_config: { provider, model_id } }),
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const body = await res.json().catch(() => ({}))
      if (body.restarting && body.machine_ok) {
        toast.success(`Model → ${model_id} — agent restarting with the new brain (~15s)`)
      } else if (body.restarting && !body.machine_ok) {
        toast.error(`Saved, but the machine didn't pick it up: ${body.machine_message || "unknown"}. Hit Reload on the agent page.`, { duration: 8000 })
      } else {
        toast.success(`Model → ${model_id}`)
      }
      // Inertia reload so the agent's top-bar meta + props refresh.
      router.reload({ only: ["agent"] })
    } catch (err) {
      toast.error(`Model change failed: ${(err as Error).message}`)
    } finally {
      setBusy(false)
    }
  }

  const currentLabel = (() => {
    const known = [...(catalog?.all ?? []), ...groupedModels.flatMap((g) => g.options)].find(
      (m) => m.provider === currentProvider && m.model_id === currentModelId,
    )
    if (known) return known.label
    if (!currentModelId) return "model"
    // Prettify legacy/custom ids: "claude-sonnet-4-20250514" → "Sonnet 4"
    return currentModelId
      .split("/")
      .pop()!
      .replace(/^claude-/, "")
      .replace(/-\d{8}$/, "") // strip trailing date stamp
      .replace(/(^|\s|-)([a-z])/g, (_, sep, c) => sep + c.toUpperCase())
  })()

  // One row, shared by the grouped view and the search results.
  const renderOption = (m: CatalogOption) => {
    const isCurrent = m.provider === currentProvider && m.model_id === currentModelId
    const keyMissing = KEY_REQUIRED_PROVIDERS.has(m.provider) && !availableLlmProviders.includes(m.provider)
    // Every model models.dev lists is selectable, but one that can't call
    // tools can't drive an agent — say so instead of quietly shipping a brain
    // that no-ops on the first tool call.
    const noTools = m.tool_call === false
    return (
      <DropdownMenuItem
        key={`${m.provider}-${m.model_id}`}
        onSelect={() => {
          if (keyMissing) {
            router.visit("/settings/credentials")
            return
          }
          apply(m.provider, m.model_id)
        }}
        className={`focus:bg-muted focus:text-foreground flex flex-col items-start gap-0.5 py-2 ${keyMissing ? "opacity-50" : ""}`}
      >
        <div className="flex w-full items-center gap-2">
          {isCurrent ? (
            <Check className="size-3.5 text-emerald-500" />
          ) : (
            <span className="size-3.5" />
          )}
          <span className="font-medium">{m.label}</span>
          {searching && (
            <span className="ml-auto shrink-0 text-[10px] text-muted-foreground">{m.provider}</span>
          )}
        </div>
        {keyMissing ? (
          <span className="pl-5.5 text-xs text-muted-foreground italic">
            Go to settings to set up your API key
          </span>
        ) : noTools ? (
          <span className="pl-5.5 text-xs text-amber-600 dark:text-amber-500">
            no tool use — can't run agent tools
          </span>
        ) : m.hint ? (
          <span className="text-muted-foreground pl-5.5 text-xs">{m.hint}</span>
        ) : null}
        {searching && (
          <span className="pl-5.5 font-mono text-[10px] text-muted-foreground/70">{m.model_id}</span>
        )}
      </DropdownMenuItem>
    )
  }

  return (
    <DropdownMenu open={open} onOpenChange={(next) => { setOpen(next); if (!next) setQuery("") }}>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 gap-1.5 font-normal hover:bg-muted hover:text-foreground"
          disabled={busy}
        >
          {busy ? <Loader2 className="size-3.5 animate-spin" /> : <Brain className="size-3.5" />}
          <span className="text-muted-foreground">Brain:</span>
          <span className="font-medium">{currentLabel}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-h-[70vh] w-80 overflow-y-auto">
        {/* Search spans the whole synced catalog (~300 models), not just the
            recommended groups — that's the point of syncing models.dev. */}
        <div className="sticky top-0 z-10 bg-popover px-2 pt-1 pb-2">
          <div className="relative">
            <Search className="pointer-events-none absolute top-1/2 left-2 size-3.5 -translate-y-1/2 text-muted-foreground" />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.stopPropagation()}
              placeholder="Search all models…"
              className="h-8 w-full rounded-md border bg-background pr-2 pl-7 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </div>

        {searching ? (
          searchResults.length > 0 ? (
            searchResults.map(renderOption)
          ) : (
            <div className="px-3 py-6 text-center text-sm text-muted-foreground">
              {loading ? "Loading catalog…" : `No model matches "${query.trim()}"`}
            </div>
          )
        ) : (
          groupedModels.map((group, i) => (
            <div key={group.group}>
              {i > 0 && <DropdownMenuSeparator />}
              <DropdownMenuLabel>{group.group}</DropdownMenuLabel>
              {group.options.map(renderOption)}
            </div>
          ))
        )}

        {!searching && catalog && (
          <div className="border-t px-3 py-2 text-[11px] text-muted-foreground">
            {catalog.all.length} models available — search to pick any of them
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
