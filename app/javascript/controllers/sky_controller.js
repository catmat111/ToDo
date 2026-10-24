import { Controller } from "@hotwired/stimulus"

// The home header's sky, animated continuously from the clock: colours blend between
// night, dawn, day and dusk, and the sun (or moon) glides along its arc. On load the
// orb rises from the horizon to where it should be; clicking the sky plays a whole day
// in a few seconds, then returns to now. The server renders the right phase first
// (DashboardPresenter#sky), so the header looks right before (or without) this.
const KEYFRAMES = [
  // hour, sky top / mid / low, orb, orb glow, far hill, near hill, ink, soft ink, stars, clouds
  [0, "#161A33", "#262B4D", "#3A3756", "#F3EBD3", "rgba(243,235,211,0.28)", "#2A2840", "#1A1828", "#F6EFE2", "rgba(246,239,226,0.78)", 1, 0],
  [4.75, "#1C2140", "#2E3158", "#4A3F5E", "#F3EBD3", "rgba(243,235,211,0.28)", "#2E2B44", "#1C1A2B", "#F6EFE2", "rgba(246,239,226,0.78)", 1, 0],
  [6.5, "#F2B9A0", "#F8D9BD", "#FCEFD8", "#F6A15B", "rgba(246,161,91,0.55)", "#D5A38A", "#9C5D3C", "#2B221B", "rgba(43,34,27,0.7)", 0, 0.8],
  [9, "#9CC9E3", "#CFE6EE", "#F4EBD9", "#F9D46B", "rgba(249,212,107,0.55)", "#A8AE78", "#6E6B41", "#2B221B", "rgba(43,34,27,0.7)", 0, 1],
  [16.5, "#A6CCE0", "#D6E6EA", "#F5EAD6", "#F9D06B", "rgba(249,208,107,0.55)", "#A8AE78", "#6E6B41", "#2B221B", "rgba(43,34,27,0.7)", 0, 1],
  [18.75, "#5B4373", "#C9705A", "#F0AE74", "#F07C3E", "rgba(240,124,62,0.6)", "#6E4A45", "#3B2A26", "#FBF3E6", "rgba(251,243,230,0.82)", 0.35, 0.3],
  [20.75, "#1E2242", "#363559", "#5A4560", "#F3EBD3", "rgba(243,235,211,0.28)", "#2E2A42", "#1C1A2A", "#F6EFE2", "rgba(246,239,226,0.78)", 0.9, 0],
  [24, "#161A33", "#262B4D", "#3A3756", "#F3EBD3", "rgba(243,235,211,0.28)", "#2A2840", "#1A1828", "#F6EFE2", "rgba(246,239,226,0.78)", 1, 0]
]
const VARS = ["--sky-top", "--sky-mid", "--sky-low", "--orb", "--orb-glow", "--hill-far", "--hill-near", "--ink", "--ink-soft"]
const RISE_MS = 1600
const DAY_MS = 20000

export default class extends Controller {
  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.classList.add("is-live")
    this.started = performance.now()
    this.demoFrom = null
    this.onClick = this.playDay.bind(this)
    this.element.addEventListener("click", this.onClick)

    if (!this.reduced) this.element.title = "Clica no céu para veres um dia inteiro passar"

    if (this.reduced) {
      this.paint(this.clockHour(), 1)
      this.timer = setInterval(() => this.paint(this.clockHour(), 1), 60_000)
    } else {
      this.frame = requestAnimationFrame(this.tick)
    }
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    clearInterval(this.timer)
    this.element.removeEventListener("click", this.onClick)
  }

  tick = (now) => {
    let hour = this.clockHour()
    if (this.demoFrom !== null) {
      const done = (now - this.demoFrom) / DAY_MS
      if (done >= 1) this.demoFrom = null
      else hour = (this.demoStartHour + ease(done) * 24) % 24
    }
    const rise = Math.min((now - this.started) / RISE_MS, 1)
    this.paint(hour, ease(rise))
    this.frame = requestAnimationFrame(this.tick)
  }

  // A whole day in a few seconds (not when clicking a link in the header).
  playDay(event) {
    if (this.reduced || event.target.closest("a, button") || this.demoFrom !== null) return
    this.demoStartHour = this.clockHour()
    this.demoFrom = performance.now()
  }

  clockHour() {
    const d = new Date()
    return d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600
  }

  // rise (0..1) lifts the orb from the horizon to its place, on load.
  paint(hour, rise) {
    const style = this.element.style
    const i = KEYFRAMES.findIndex((k, n) => hour >= k[0] && hour < KEYFRAMES[n + 1][0])
    const [a, b] = [KEYFRAMES[i], KEYFRAMES[i + 1]]
    const f = (hour - a[0]) / (b[0] - a[0])
    VARS.forEach((name, n) => style.setProperty(name, mix(a[n + 1], b[n + 1], f)))
    style.setProperty("--stars", (a[10] + (b[10] - a[10]) * f).toFixed(3))
    style.setProperty("--clouds", (a[11] + (b[11] - a[11]) * f).toFixed(3))

    // The sun crosses 05:30 → 20:30, the moon 20:30 → 05:30; both left to right.
    const night = hour >= 20.5 || hour < 5.5
    const t = night ? (hour >= 20.5 ? hour - 20.5 : hour + 3.5) / 9 : (hour - 5.5) / 15
    style.setProperty("--sky-t", Math.min(Math.max(t, 0), 1).toFixed(4))
    style.setProperty("--sky-rise", rise.toFixed(3))
    this.element.dataset.sky = night ? "night" : hour < 8 ? "dawn" : hour < 18 ? "day" : "dusk"
  }
}

function ease(x) {
  return x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2
}

// Blends two colours ("#rrggbb" or "rgba(r,g,b,a)") by f (0..1).
function mix(from, to, f) {
  const [r1, g1, b1, a1] = rgba(from)
  const [r2, g2, b2, a2] = rgba(to)
  const c = (x, y) => Math.round(x + (y - x) * f)
  return `rgba(${c(r1, r2)}, ${c(g1, g2)}, ${c(b1, b2)}, ${(a1 + (a2 - a1) * f).toFixed(3)})`
}

function rgba(color) {
  if (color.startsWith("#")) {
    const n = parseInt(color.slice(1), 16)
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1]
  }
  return color.match(/[\d.]+/g).map(Number)
}
