import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.element.classList.contains("flash--notice")) {
      this.timeout = setTimeout(() => this.dismiss(), 6000)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}
