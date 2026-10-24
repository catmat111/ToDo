import { Controller } from "@hotwired/stimulus"

// A flash message: notices close by themselves after a few seconds, alerts stay until
// closed. Leaving fades it out (see #flash in flash.css).
export default class extends Controller {
  connect() {
    if (this.element.classList.contains("flash--notice")) {
      this.timeout = setTimeout(() => this.dismiss(), 5000)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.classList.add("is-leaving")
    setTimeout(() => this.element.remove(), 250)
  }
}
