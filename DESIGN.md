---
version: alpha
name: "TikTok"
slug: "tiktok"
source: "https://www.tiktok.com/"
extractedAt: "2026-05-20"
description: "High-contrast entertainment system built on black-and-white utility UI, sharpened by electric cyan and hot coral accents, TikTok Sans typography, full-bleed media, and a fast-switching rhythm between expressive culture surfaces and stripped-back operational panels."

colors:
  primary: "#000000"
  accent: "#FE2C55"
  accentHover: "#E6254E"
  accentPressed: "#D61F46"
  ink: "#161823"
  body: "#161823"
  muted: "#6B7280"
  canvas: "#FFFFFF"
  surface: "#FFFFFF"
  surfaceAlt: "#F7F7F8"
  border: "#E5E7EB"
  borderStrong: "#C7CAD1"
  link: "#161823"
  success: "#0F9D58"
  warning: "#F59E0B"
  error: "#D61F46"
  signature-cyan: "#25F4EE"
  signature-coral: "#FE2C55"
  signature-shadow-cyan: "#D9FFFD"
  signature-shadow-coral: "#FFD8E1"
  business-emerald: "#00C2A8"
  business-glint: "#DFFCF3"
  business-blaze: "#FFE8EF"
  footer-bg: "#000000"
  help-surface: "#FAFAFA"
  on-primary: "#FFFFFF"
  on-dark: "#FFFFFF"

typography:
  display:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 64px
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.03em"
  hero:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 48px
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-0.025em"
  headline-lg:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 40px
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title-lg:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 32px
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.015em"
  title-md:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 24px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  title-sm:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.005em"
  button:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 16px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  label:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.005em"
  body:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0em"
  caption:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0em"
  legal:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.01em"
  metric-display:
    fontFamily: "TikTok Sans, Inter, Arial, sans-serif"
    fontSize: 56px
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.03em"

rounded:
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  pill: 9999px

spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  section: 80px

components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "12px 20px"
  button-primary-active:
    backgroundColor: "{colors.accentPressed}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
  button-secondary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "12px 20px"
  button-outline:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "12px 20px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
  button-video-pill:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "8px 14px"
  card-feature:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "24px"
  card-metric:
    backgroundColor: "{colors.surfaceAlt}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
    padding: "24px"
  card-case-study:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
    padding: "24px"
  nav-global:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "0px"
    padding: "16px 24px"
  nav-business-subnav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "0px"
    padding: "10px 0"
  input-search:
    backgroundColor: "{colors.help-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "12px 16px"
  footer-global:
    backgroundColor: "{colors.footer-bg}"
    textColor: "{colors.on-dark}"
    rounded: "0px"
    padding: "48px 24px"
  hashtag-rail:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0px"
  hero-video-frame:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-dark}"
    rounded: "{rounded.xl}"
    padding: "0px"
  business-glint-panel:
    backgroundColor: "{colors.business-glint}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
    padding: "24px"
  business-blaze-panel:
    backgroundColor: "{colors.business-blaze}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
    padding: "24px"
---

**Overview**
TikTok’s visual identity is built on contrast, speed, and immediacy. The core system is minimal rather than ornamental: `{colors.canvas}` backgrounds, `{colors.ink}` text, restrained borders, and interface chrome that stays out of the way so video, creator identity, and conversion prompts take visual priority. The distinctive layer comes from the brand’s signature offsets of `{colors.signature-cyan}` and `{colors.signature-coral}`, which act less like a full-page palette and more like electric highlights around black-and-white media and typography.

There are at least three visible modes. The consumer brand surface on `tiktok.com/about` is bold, media-led, and headline-heavy. The business-marketing surface on `ads.tiktok.com/business` keeps the same typographic DNA but introduces brighter campaign panels, stat cards, and full-funnel promotional modules. The support surface on `support.tiktok.com` is the most stripped back: lower contrast in layout density, quieter surfaces, and a utility-first hierarchy designed for scanning. Across all three, the recognizable throughline is TikTok Sans, generous headline scale, rounded but not soft containers, and a pace that alternates punchy statements with dense, functional information.

Key Characteristics
- Use `{colors.primary}` and `{colors.canvas}` as the default stage, then deploy `{colors.signature-cyan}` and `{colors.signature-coral}` as energetic punctuations rather than ambient fills.
- Favor `{typography.display}` and `{typography.hero}` for short, declarative statements with tight tracking and visible line breaks.
- Keep UI shells simple so media, metrics, or cultural tags such as `#BookTok` carry the brand expression.
- Apply `{rounded.md}` to `{rounded.xl}` consistently; the system is rounded, but not bubbly.
- Build hierarchy through scale, rhythm, and full-bleed imagery more than through heavy shadow stacks.
- Switch tone by context: expressive on marketing pages, analytical on business pages, neutral on support pages.
- Let social proof modules, case studies, hashtag rails, and creator-oriented feature blocks do the distinctive product storytelling.

**Colors**
Primary & Action
- `{colors.primary}` `#000000`: The deepest brand anchor. It appears in logos, footer fields, dark media frames, and high-contrast headline moments.
- `{colors.accent}` `#FE2C55`: The most recognizable action color. It is the closest thing TikTok has to a universal CTA tone and carries the brand’s hot-coral energy.
- `{colors.accentHover}` `#E6254E`: A darker coral used for active and hover states so primary CTAs retain punch without introducing a new hue family.
- `{colors.accentPressed}` `#D61F46`: The pressed state for high-emphasis action. It keeps the brand in the same coral lane while deepening contrast.
- `{colors.link}` `#161823`: Links often read as text-first rather than conventionally blue; this keeps the system editorial and product-like.

Surfaces
- `{colors.canvas}` `#FFFFFF`: The default page field across About, Business, and Support pages. It keeps video, photography, and numerics feeling crisp.
- `{colors.surface}` `#FFFFFF`: Reused for cards that should feel flush with the page rather than deeply elevated.
- `{colors.surfaceAlt}` `#F7F7F8`: A soft neutral used for secondary cards, utility backgrounds, and analytic modules where pure white would feel too stark.
- `{colors.help-surface}` `#FAFAFA`: A slightly quieter support/help background used to reduce contrast fatigue in text-dense utility contexts.
- `{colors.footer-bg}` `#000000`: A hard visual stop for global footers and brand resets at the bottom of longer marketing pages.

Neutrals & Text
- `{colors.ink}` `#161823`: The main text and structural neutral. It is softer than pure black and works better for dense UI reading.
- `{colors.body}` `#161823`: Body copy follows the same dark neutral as headings, reinforcing TikTok’s direct, no-nonsense voice.
- `{colors.muted}` `#6B7280`: Used for metadata, helper copy, source labels, and reduced-priority information.
- `{colors.border}` `#E5E7EB`: Light dividers, search shells, and card outlines. TikTok prefers minimal separators over visibly chromed frames.
- `{colors.borderStrong}` `#C7CAD1`: For more explicit boundaries in utility contexts where light gray would disappear.

Semantic
- `{colors.success}` `#0F9D58`: Conservative green reserved for positive status or growth indication; not a visible centerpiece of the brand.
- `{colors.warning}` `#F59E0B`: Used for caution without introducing red conflict.
- `{colors.error}` `#D61F46`: Error and destructive emphasis stay close to TikTok’s coral system rather than breaking into an unrelated red.

Brand-specific Signatures
- `{colors.signature-cyan}` `#25F4EE`: The electric cyan from the TikTok mark. Best used as a sharp offset, edge highlight, or accent object, not as a large reading surface.
- `{colors.signature-coral}` `#FE2C55`: The companion hot coral that signals energy, action, and creator-side excitement.
- `{colors.signature-shadow-cyan}` `#D9FFFD`: A pale cyan wash that can support the signature color in business illustrations or soft panels without overpowering content.
- `{colors.signature-shadow-coral}` `#FFD8E1`: The soft coral counterpart, useful for lightweight highlight panels.
- `{colors.business-emerald}` `#00C2A8`: A business-facing growth accent that sits comfortably beside TikTok’s consumer cyan without duplicating it.
- `{colors.business-glint}` `#DFFCF3`: Derived from the observed “glint” naming on Business pages. It reads like a fresh, mint-tinted success surface for marketing modules.
- `{colors.business-blaze}` `#FFE8EF`: Derived from the observed “blaze” naming on Business pages. It extends the brand coral into a large, soft case-study or promo surface.

**Typography**
TikTok’s typography is now officially centered on TikTok Sans, introduced by TikTok across “in-app and brand touchpoints” and described as visually larger than the previous Proxima Nova with increased line height and refined letter spacing. That matters: the brand does not just use a trendy sans; it uses a custom family designed to improve speed, clarity, and anti-spoof legibility while keeping a broad, expressive silhouette. Fallbacks should stay neutral and compact, such as `Inter` and `Arial`.

| Token | Size | Weight | Line height | Letter spacing |
|---|---:|---:|---:|---:|
| `{typography.display}` | 64px | 700 | 1.05 | -0.03em |
| `{typography.hero}` | 48px | 700 | 1.08 | -0.025em |
| `{typography.headline-lg}` | 40px | 700 | 1.10 | -0.02em |
| `{typography.title-lg}` | 32px | 700 | 1.15 | -0.015em |
| `{typography.title-md}` | 24px | 700 | 1.20 | -0.01em |
| `{typography.title-sm}` | 20px | 600 | 1.25 | -0.005em |
| `{typography.button}` | 16px | 600 | 1.20 | -0.01em |
| `{typography.label}` | 14px | 600 | 1.25 | -0.005em |
| `{typography.body}` | 16px | 400 | 1.50 | 0em |
| `{typography.caption}` | 13px | 400 | 1.40 | 0em |
| `{typography.legal}` | 12px | 400 | 1.40 | 0.01em |
| `{typography.metric-display}` | 56px | 700 | 1.00 | -0.03em |

Principles
- Push display text large and tight. TikTok headlines are meant to feel immediate, not elegant or literary.
- Use heavier weights early in the hierarchy. The system prefers bold entry points and calmer secondary copy.
- Keep body copy straightforward. TikTok’s distinction is not in ornate paragraph styling but in what surrounds the text.
- Preserve open counters and legibility. This aligns with TikTok Sans’s stated readability improvements and supports dense UI use.
- Let numerics feel oversized. Metrics and percentages on Business pages act like mini-headlines rather than table data.

**Layout**
The spacing rhythm is compact at the component level and generous at the section level. `{spacing.xs}` through `{spacing.md}` handle label-to-copy and button padding, while `{spacing.xl}` and `{spacing.section}` structure large editorial page bands. Observed pages suggest a typical desktop content container in the 1200-1280px range, with full-bleed media and stat blocks breaking out when emphasis is needed. Navigation is usually a shallow top rail plus, on Business surfaces, a secondary taxonomy rail for goals, industries, tools, or resources.

Whitespace is used strategically rather than luxuriously. TikTok does not aim for airy minimalism in the Apple sense; it aims for scanning speed. Dense informational bands are followed by abrupt breathing space, then by another high-impact module. The result is a pulse: crowded, clear, crowded, clear.

**Elevation & Depth**
Depth is restrained. The visible hierarchy on official pages comes far more from scale, contrast, rounded containers, full-bleed imagery, and section sequencing than from heavy shadows. A conservative implementation can use either no shadow or a single soft value such as `0 8px 24px rgba(22, 24, 35, 0.08)` for floating cards, but shadow should never become a stylistic lead.

TikTok creates emphasis through three other methods first: dark-vs-light blocking, large numerics, and media frames such as `{components.hero-video-frame}`. On Business pages, color-coded panels like `{components.business-glint-panel}` and `{components.business-blaze-panel}` provide “depth by tint” instead of “depth by blur.”

**Components**
Buttons
- `{components.button-primary}` is the direct-response CTA. It should read as the fastest path forward and typically uses `{colors.accent}` on white or mixed media backgrounds.
- `{components.button-primary-active}` deepens into `{colors.accentPressed}` without changing shape. The state logic is tonal, not structural.
- `{components.button-secondary}` is the dark alternative for cases where the page is already loud and the CTA needs authority more than heat.
- `{components.button-outline}` is for lower-commitment actions such as “Learn more” on white surfaces. Keep the border subtle; TikTok’s outline buttons should not feel enterprise-heavy.
- `{components.button-ghost}` works in tertiary rails, utility navigation, or low-priority actions where only the text weight should change.
- `{components.button-video-pill}` is the softer, culture-adjacent control style. Use it around category chips, creator filters, or lightweight on-media utility.

Cards & Containers
- `{components.card-feature}` is the baseline marketing card: rounded, clean, low-chrome, and content-led.
- `{components.card-metric}` supports large percentages or short proofs. The point is not decorative framing; it is giving numbers enough room to act as statements.
- `{components.card-case-study}` should hold a brand story, results, and CTA in one contained module. Use it when evidence needs more narrative structure than a metric card.
- `{components.hero-video-frame}` is a signature TikTok pattern. Even when the page is not literally playing a video, content is often framed as if it belongs to a full-screen media environment.
- `{components.business-glint-panel}` and `{components.business-blaze-panel}` are business-specific presentation surfaces. They bring warmth and freshness without breaking the base black-white grammar.

Inputs & Forms
- `{components.input-search}` fits TikTok’s utility mode best: pill-shaped, quiet, soft-surface, and minimal in border treatment. It should feel fast and familiar, not technical.
- Forms should prefer clear labels, short helper text in `{typography.caption}`, and restrained field chrome. Support surfaces especially should feel scannable before they feel branded.

Navigation
- `{components.nav-global}` is a simple top strip with strong text hierarchy and little ornament. Keep logo contrast high and rely on spacing, not separators.
- `{components.nav-business-subnav}` adds taxonomy for goals, industries, tools, and resources. It behaves more like an information shelf than a flashy tab bar.
- `{components.footer-global}` is a dense, black anchor with multiple link columns. It resets the page into a more corporate register and should feel reliable rather than playful.

Pricing
- No first-party public pricing landing page was directly confirmed on `tiktok.com` during this extraction. Cost and billing information were observed in Ads Manager help content instead of a polished pricing table surface.
- If a pricing-style screen must be generated, borrow from `{components.card-metric}` and `{typography.metric-display}` rather than inventing a SaaS pricing matrix aesthetic.

Signature Components
- `{components.hashtag-rail}` is core to TikTok’s brand language. Hashtag clusters function as cultural wayfinding and should feel like bold textual artifacts, not tiny filter chips.
- Success-story carousels with creator or brand proof are a recurring product-marketing pattern. They should combine oversized result figures, compact narrative copy, and one decisive CTA.
- Multi-step “How to get started” blocks on Business pages use short headlines, numeric sequencing, and screenshot/graphic support. These modules should feel instructional but still brisk.

**Do's and Don'ts**
Do's
- Use `{colors.primary}` and `{colors.canvas}` as the dominant contrast pair before introducing accent colors.
- Apply `{colors.signature-cyan}` and `{colors.signature-coral}` in short, high-energy moments such as CTA focus, logo-adjacent accents, or supporting shapes.
- Set hero copy in `{typography.display}` or `{typography.hero}` with tight tracking and short lines.
- Keep action buttons at `{rounded.md}` so they feel contemporary and mobile-native without turning soft.
- Build proof modules with `{typography.metric-display}` and `{components.card-metric}` instead of burying numbers in body text.
- Use `{components.hero-video-frame}` or other media-first containers when a section is meant to feel natively TikTok.
- Shift into `{colors.help-surface}` and `{components.input-search}` for support or documentation contexts that need calmer scanning.

Don'ts
- Do not flood whole pages with `{colors.signature-cyan}` or `{colors.signature-coral}`; TikTok uses them as shocks, not wallpaper.
- Do not replace `{typography.display}` with elegant serif or airy fashion typography; the brand voice is direct and kinetic.
- Do not add glassmorphism, neon gradients, or oversized glow effects unless a source surface explicitly shows them.
- Do not round cards beyond `{rounded.xl}`; overly soft corners dilute the sharpness of the system.
- Do not make links blue-by-default when `{colors.link}` can keep them integrated with the text system.
- Do not rely on deep shadow stacks to create hierarchy; prefer scale, tint, and contrast.
- Do not turn support screens into marketing pages with loud accent fills and oversized CTA clusters.
- Do not invent a polished SaaS pricing table style that was not directly observed in the source ecosystem.

**Responsive Behavior**
| Breakpoint | Min width | Typical behavior |
|---|---:|---|
| `phone-sm` | 320px | Single column, compressed nav, media-first stacking |
| `phone-lg` | 414px | Full-width buttons, larger headline wrapping, stronger thumb zones |
| `tablet` | 768px | Two-column opportunities for metrics and feature cards |
| `laptop` | 1024px | Full navigation and mixed media/text section pairings |
| `desktop` | 1280px | Multi-card grids, full taxonomy rails, wider hero layouts |
| `desktop-wide` | 1440px | Larger whitespace buffers and more generous breakout media |

Touch targets should stay at or above 44px height for key actions, especially any primary CTA derived from `{components.button-primary}` or search entry based on `{components.input-search}`.

Collapsing strategy
- Collapse secondary navigation categories into drawers or horizontal scroll before shrinking primary brand actions.
- Stack `{components.card-feature}` and `{components.card-case-study}` vertically on phone widths rather than squeezing to narrow two-column cards.
- Allow `{typography.display}` to step down to `{typography.headline-lg}` on smaller screens before reducing weight.
- Convert hashtag rows into wrapped lines, not tiny truncated pills, so cultural labels stay legible.
- Keep metric figures large; reduce surrounding copy first, not the number itself.

Images and media should crop boldly. TikTok is comfortable with immersive framing, partial previews, and edge-to-edge visual modules as long as key focal content remains centered and action text does not fall into unsafe crop zones.

**Iteration Guide**
1. Check whether the first read is dominated by `{colors.primary}`, `{colors.canvas}`, and one of the signature accents instead of a generic SaaS palette.
2. Verify every major headline uses a defined TikTok Sans token such as `{typography.hero}` or `{typography.title-lg}`, not arbitrary browser defaults.
3. Audit CTAs for contrast and hierarchy: `{components.button-primary}` should clearly outrank `{components.button-outline}`.
4. Review rounding across controls and cards. If anything exceeds `{rounded.xl}` or mixes many corner systems, it is drifting.
5. Inspect whether proof is presented through `{typography.metric-display}` and concise cards rather than long explanatory paragraphs.
6. Confirm that media or creator-oriented framing appears somewhere through `{components.hero-video-frame}`, `{components.hashtag-rail}`, or case-study storytelling.
7. Make sure support-like views use quieter surfaces such as `{colors.help-surface}` and do not overuse accent fills.
8. Remove any decorative effects that are carrying too much of the composition; TikTok should feel high-energy through content rhythm, not through ornament alone.

**Known Gaps**
This extraction is strongest on brand structure, type direction, content rhythm, and cross-surface component patterns because those were observed directly from official TikTok About, TikTok for Business, Newsroom, Support, and TikTok Sans pages on May 20, 2026. The introduction of TikTok Sans, its replacement of Proxima Nova, its larger visual size, and increased line-height are directly documented by TikTok.

Exact CSS token values for web spacing, font sizes, corner radii, and shadows were not available through the accessible page text layer, and direct browser inspection of some rendered pages was blocked by browser security policy during research. The numeric values in YAML for spacing, radii, and type scale are therefore conservative reconstructions based on visible hierarchy, common responsive web patterns on the official pages, and the documented behavior of TikTok Sans.

The Business subpalette names `{colors.business-glint}` and `{colors.business-blaze}` are grounded in observed official asset labels on TikTok for Business pages, but their exact hex values are derived approximations rather than directly published tokens. Likewise, no polished public pricing page on `tiktok.com` was directly confirmed, so pricing guidance here is intentionally minimal and derived from Ads Manager help patterns rather than a dedicated branded pricing surface.
