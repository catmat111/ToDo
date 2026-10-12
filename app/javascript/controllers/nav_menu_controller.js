import { Controller } from "@hotwired/stimulus"

// Masthead drop-down: hover and keyboard focus open it through CSS; the toggle button
// opens it on touch screens. Closes on Escape or a click elsewhere.
export default class extends Controller {
  static targets = ["toggle", "menu"]

  toggle(event) {
    event.preventDefault()
    this.element.classList.contains("is-open") ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("is-open")
    this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.element.classList.remove("is-open")
    this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  closeOnEscape(event) {
    if (event.key !== "Escape" || !this.element.classList.contains("is-open")) return
    this.close()
    this.toggleTarget.focus()
  }

  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
