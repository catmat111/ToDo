import { Controller } from "@hotwired/stimulus"

// Copies the generated job search URL to the clipboard and announces the result.
export default class extends Controller {
  static targets = [ "label", "status" ]

  async copy(event) {
    const url = event.params.url
    if (!url) return

    try {
      await navigator.clipboard.writeText(url)
      this.announce("Link copiado")
    } catch {
      this.announce("Não foi possível copiar o link")
    }
  }

  announce(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
    if (!this.hasLabelTarget) return

    const original = this.labelTarget.dataset.original || this.labelTarget.textContent
    this.labelTarget.dataset.original = original
    this.labelTarget.textContent = message
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => { this.labelTarget.textContent = original }, 2000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
