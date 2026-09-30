import { Controller } from "@hotwired/stimulus"

// Collapsible navigation on narrow screens.
export default class extends Controller {
  static targets = ["panel", "toggle"]

  toggle() {
    const open = this.element.classList.toggle("is-nav-open")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  close(event) {
    if (event.key === "Escape") this.element.classList.remove("is-nav-open")
  }
}
