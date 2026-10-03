import { Controller } from "@hotwired/stimulus"

// Previews a photo link in the profile avatar (#avatar-preview) when Enter is pressed
// or the field changes. Enter no longer submits the form; "Guardar" does.
const GIPHY_PAGE = /^https?:\/\/(?:www\.)?giphy\.com\/(?:embed|gifs)\/(?:[\w-]*-)?(\w+)\/?$/i

export default class extends Controller {
  static targets = ["input", "status"]

  preview() {
    const url = this.directUrl(this.inputTarget.value.trim())
    if (!url) return
    if (!/^https?:\/\//i.test(url)) return this.say("O link tem de começar por https://", true)

    const avatar = document.querySelector("#avatar-preview .avatar")
    if (!avatar) return

    this.say("A carregar a pré-visualização…")
    const img = new Image()
    img.alt = ""
    img.referrerPolicy = "no-referrer"
    img.onload = () => {
      avatar.textContent = ""
      avatar.appendChild(img)
      this.say("Pré-visualização — clica em Guardar para manter.")
    }
    img.onerror = () => this.say("Este link não é uma imagem. Copia o endereço da própria imagem (botão direito → «Copiar endereço da imagem»).", true)
    img.src = url
  }

  // Same conversion the server does for Giphy page/embed links.
  directUrl(url) {
    const match = url.match(GIPHY_PAGE)
    return match ? `https://media.giphy.com/media/${match[1]}/giphy.gif` : url
  }

  say(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("field__error", error)
  }
}
