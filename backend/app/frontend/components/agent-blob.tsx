import { Blobatar } from "blobatar/react"
import "blobatar/motion.css"

/**
 * The face of an agent, a template, or anyone else who shows up in the product.
 *
 * Appearance is derived entirely from `name`, so the same agent looks the same
 * everywhere it appears — sidebar, card, chat header — without us storing an
 * avatar. Any string works; use the most stable identifier you have at the call
 * site (a template slug beats a template title, which gets renamed).
 *
 * `animate` defaults to `"hover"`, which animates one blobatar at a time. Grids
 * want that: continuous ambient motion across forty faces is noise, and forty
 * live animations is work. Pass `"always"` for the single-blobatar case — a
 * hero, a profile header — and `false` where the face is decoration inside
 * something else that already moves.
 */
export function AgentBlob({
  name,
  size,
  className,
  animate = "hover",
  background = false,
}: {
  name: string
  size?: number
  className?: string
  animate?: "hover" | "always" | false
  /** Off by default: a bare silhouette is what makes two blobatars tell apart. */
  background?: "squircle" | "circle" | "square" | false
}) {
  // The prop union is deliberate upstream: `onLoad` stops type-checking the
  // moment animation is on, because a static blobatar is an <img> and an
  // animated one is inline SVG. Branching here keeps that honest.
  if (animate === false) {
    return (
      <Blobatar
        name={name}
        size={size}
        background={background}
        title={name}
        className={className}
      />
    )
  }

  return (
    <Blobatar
      name={name}
      size={size}
      background={background}
      title={name}
      animate={animate}
      className={className}
    />
  )
}
