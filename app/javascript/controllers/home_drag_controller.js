import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Drag tasks on the home page: from the backlog (or "A seguir") onto "Hoje" to do them
// today, or from "Hoje" onto a tag in the backlog to keep them there without a date.
// Items carry data-plan-url; drop zones carry data-drop-zone ("today" / "backlog")
// and, for a tag, data-tag-id. The server answers with a page refresh (morphed).
export default class extends Controller {
  start(event) {
    const item = event.target.closest("[data-plan-url]")
    if (!item) return
    this.item = item
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", item.dataset.planUrl)
    requestAnimationFrame(() => item.classList.add("is-dragging"))
    this.element.classList.add("is-dragging-task")
  }

  end() {
    this.item?.classList.remove("is-dragging")
    this.item = null
    this.element.classList.remove("is-dragging-task")
    this.element.querySelectorAll(".is-drop-target").forEach((zone) => zone.classList.remove("is-drop-target"))
  }

  over(event) {
    const zone = this.zoneFor(event)
    if (!zone) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.element.querySelectorAll(".is-drop-target").forEach((other) => other !== zone && other.classList.remove("is-drop-target"))
    zone.classList.add("is-drop-target")
  }

  leave(event) {
    const zone = event.target.closest("[data-drop-zone]")
    if (zone && !zone.contains(event.relatedTarget)) zone.classList.remove("is-drop-target")
  }

  async drop(event) {
    const zone = this.zoneFor(event)
    if (!zone) return
    event.preventDefault()
    const item = this.item
    this.end()

    const body = new FormData()
    body.append("to", zone.dataset.dropZone)
    if (zone.dataset.tagId) body.append("tag_id", zone.dataset.tagId)
    item.classList.add("is-moving")
    const response = await fetch(item.dataset.planUrl, {
      method: "PATCH",
      body,
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    })
    item.classList.remove("is-moving")
    Turbo.renderStreamMessage(await response.text())
  }

  // A zone the dragged task can go to (not the list it is already in).
  zoneFor(event) {
    const zone = event.target.closest("[data-drop-zone]")
    if (!zone || !this.item) return null
    if (zone.dataset.dropZone === "today" && zone.contains(this.item)) return null
    if (zone.dataset.dropZone === "backlog" && this.item.dataset.tagIds?.split(" ").includes(zone.dataset.tagId) && !this.item.dataset.dated) return null
    return zone
  }
}
