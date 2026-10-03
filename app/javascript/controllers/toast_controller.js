import { Controller } from "@hotwired/stimulus"

// Live notification pop-up (appended by a Turbo Stream broadcast). Disappears on
// its own after a while, but stays while hovered so it can still be clicked.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 10000 } }

  connect() {
    this.start()
    this.element.addEventListener("mouseenter", this.stop)
    this.element.addEventListener("mouseleave", this.start)
  }

  disconnect() {
    this.stop()
  }

  start = () => {
    this.stop()
    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  stop = () => {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("is-leaving")
    setTimeout(() => this.element.remove(), 200)
  }
}
