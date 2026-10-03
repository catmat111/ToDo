import { Controller } from "@hotwired/stimulus"

// Bottom-right "post-it" chat for adding tasks due today.
export default class extends Controller {
  static targets = ["panel", "toggle", "input", "messages"]

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.element.classList.add("is-open")
    this.scrollToEnd()
    this.inputTarget.focus()
  }

  close() {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.element.classList.remove("is-open")
    this.toggleTarget.focus()
  }

  // After the server answered: clear the box and show the new bubbles.
  sent(event) {
    if (!event.detail.success) return
    this.inputTarget.value = ""
    this.inputTarget.focus()
    requestAnimationFrame(() => this.scrollToEnd())
  }

  scrollToEnd() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
