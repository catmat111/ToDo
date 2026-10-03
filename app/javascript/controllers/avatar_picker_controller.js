import { Controller } from "@hotwired/stimulus"

// Profile photo picker: previews the chosen image straight away and, on the profile
// page, saves it immediately (autosubmit). Mirrors the server-side limits.
const TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif"]
const MAX_BYTES = 5 * 1024 * 1024

export default class extends Controller {
  static targets = ["input", "preview", "status"]
  static values = { autosubmit: Boolean }

  chosen() {
    const file = this.inputTarget.files[0]
    if (!file) return

    if (!TYPES.includes(file.type)) return this.reject("Escolhe uma imagem PNG, JPG, WebP ou GIF.")
    if (file.size > MAX_BYTES) return this.reject("A imagem tem de ter no máximo 5 MB.")

    this.showPreview(file)
    if (this.autosubmitValue) {
      this.statusTarget.textContent = "A guardar…"
      this.inputTarget.form.requestSubmit()
    } else {
      this.statusTarget.textContent = "Pré-visualização — clica em Guardar para manter."
    }
  }

  showPreview(file) {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(file)
    const avatar = this.previewTarget.querySelector(".avatar")
    avatar.textContent = ""
    const img = document.createElement("img")
    img.src = this.objectUrl
    img.alt = ""
    avatar.appendChild(img)
  }

  reject(message) {
    this.inputTarget.value = ""
    this.statusTarget.textContent = message
  }

  disconnect() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }
}
