import { Head, Link, usePage } from "@inertiajs/react"
import { ArrowRight, GitBranch } from "lucide-react"
import { useEffect, useRef } from "react"

import { StatusDot } from "@/components/brand"
import { LandingFooter } from "@/components/landing/landing-footer"
import { LandingNav } from "@/components/landing/landing-nav"
import { Button } from "@/components/ui/button"
import { dashboardPath, newUserRegistrationPath } from "@/routes"
import type { SharedProps } from "@/types"

function useCta() {
  const { auth } = usePage<SharedProps>().props
  const signedIn = !!auth?.user
  return {
    href: signedIn ? dashboardPath() : newUserRegistrationPath(),
    label: signedIn ? "Open dashboard" : "Get started",
  }
}

export default function LandingPage() {
  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground antialiased">
      <Head title="Sentrel — AI employees that live inside your tools" />
      <LandingNav />
      <Hero />
      <LandingFooter />
    </div>
  )
}

/**
 * One screen: a face, a sentence, two buttons.
 *
 * The face is a rendered clip rather than a live blobatar — it grows in and
 * settles, which the runtime renderer has no equivalent for. Two things about
 * the source file drive the markup:
 *
 *  - It has a white backdrop, not a transparent one. The circular clip is what
 *    turns that into a deliberate disc instead of a white square on a dark
 *    page, and `scale-[1.6]` pushes the backdrop past the clip so the body
 *    fills it. Much past that and the eyes start clipping on the hardest
 *    tilt, around 1.6s.
 *  - It is an intro, not a seamless loop: it opens on a near-empty white disc
 *    and ends full-bleed. `loop` would therefore cut to a white flash every
 *    2.7s, which is why the wrap is done by hand below.
 */

/** Where a repeat starts — past the grow-in, where the frame already matches
 *  the clip's last one. Restarting at 0 is what makes a plain loop flash. */
const LOOP_FROM = 0.45
const WRAP_FADE_MS = 220

function Hero() {
  const cta = useCta()
  const video = useRef<HTMLVideoElement>(null)

  useEffect(() => {
    const el = video.current
    if (!el) return

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      // Reduced motion gets the destination, not the journey: hold the last
      // frame, where the blobatar is settled and full-size.
      el.pause()
      const settle = () => {
        el.currentTime = el.duration
      }
      if (el.readyState >= 1) settle()
      else el.addEventListener("loadedmetadata", settle, { once: true })
      return
    }

    // Loop by hand so the intro plays in full once and every repeat after it
    // starts from a frame that already matches the one it is replacing. The
    // short dip covers the small difference that is left.
    let timer = 0
    const wrap = () => {
      el.style.opacity = "0"
      timer = window.setTimeout(() => {
        el.currentTime = LOOP_FROM
        void el.play()
        el.style.opacity = "1"
      }, WRAP_FADE_MS)
    }
    el.addEventListener("ended", wrap)
    return () => {
      el.removeEventListener("ended", wrap)
      window.clearTimeout(timer)
    }
  }, [])

  return (
    <section className="relative isolate flex flex-1 items-center overflow-hidden">
      {/* One soft glow behind the face — the whole ambient layer. */}
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-1/2 -z-10 h-[46rem] w-[46rem] -translate-x-1/2 -translate-y-[60%] rounded-full opacity-60 blur-3xl animate-blob-a"
        style={{
          background:
            "radial-gradient(closest-side, var(--indigo-glow) 0%, var(--cyan-glow) 45%, transparent 72%)",
        }}
      />

      <div className="mx-auto flex w-full max-w-3xl flex-col items-center px-6 pb-24 pt-36 text-center md:pb-28 md:pt-40">
        <div className="size-[220px] overflow-hidden rounded-full drop-shadow-[0_24px_60px_var(--indigo-glow)] md:size-[260px]">
          <video
            ref={video}
            src="/hero-blobatar.mp4"
            autoPlay
            muted
            playsInline
            preload="auto"
            aria-label="A Sentrel agent"
            className="block w-full scale-[1.6] transition-opacity"
            style={{ transitionDuration: `${WRAP_FADE_MS}ms` }}
          />
        </div>

        <h1 className="text-hero mt-10 text-foreground">
          Meet your{" "}
          <span className="serif-italic text-muted-foreground">new</span>{" "}
          <span className="serif-italic text-[var(--color-indigo)]">AI team</span>.
        </h1>

        <p className="mt-7 max-w-lg text-[17px] leading-relaxed text-muted-foreground">
          Hire specialists — sales, support, ops, engineering. Each one lives
          inside Slack, Gmail, your CRM, and 250+ other tools your team already
          uses. They draft, you approve, the work ships.
        </p>

        <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
          <Button
            asChild
            size="lg"
            className="group h-12 gap-1.5 px-6 text-sm shadow-[0_0_0_1px_var(--color-indigo),0_12px_32px_-8px_var(--indigo-glow)]"
          >
            <Link href={cta.href}>
              {cta.label}
              <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
            </Link>
          </Button>
          <Button asChild size="lg" variant="outline" className="h-12 px-6 text-sm">
            <Link href="/use-cases">Browse 100+ roles</Link>
          </Button>
        </div>

        <div className="mt-9 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 font-mono text-[11px] uppercase tracking-[0.14em] text-muted-foreground/70">
          <span className="flex items-center gap-2">
            <StatusDot status="online" pulse />
            operational
          </span>
          <span className="opacity-40">·</span>
          <span>no credit card</span>
          <span className="opacity-40">·</span>
          <span>Slack · Gmail · 250+ apps</span>
          <span className="opacity-40">·</span>
          {/* "Source available", not "open source": the repo is public but
              carries no LICENSE, and the README states a custom
              source-available license is still TBD. Flip the wording once an
              OSI license actually lands. */}
          <a
            href="https://github.com/SentrelAI/sentrel"
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 transition-colors hover:text-foreground"
          >
            <GitBranch className="size-3" />
            source available
          </a>
        </div>
      </div>
    </section>
  )
}
