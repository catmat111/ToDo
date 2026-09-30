import { Controller } from "@hotwired/stimulus"

// Tag form: keeps the "custom colour" radio in sync with the colour picker
// and updates the live chip preview as the name/colour change.
export default class extends Controller {
  static targets = [ "name", "picker", "customRadio", "preview" ]

  connect() {
    this.preview()
  }

  pick() {
    this.customRadioTarget.checked = true
    this.preview()
  }

  preview() {
    if (this.hasPickerTarget && this.hasCustomRadioTarget) {
      this.customRadioTarget.value = this.pickerTarget.value.toUpperCase()
    }

    const checked = this.element.querySelector("input[type=radio][name='tag[color]']:checked")
    const color = checked ? checked.value : ""

    if (this.hasPreviewTarget) {
      if (/^#[0-9a-f]{6}$/i.test(color)) {
        this.previewTarget.style.setProperty("--chip-color", color)
      } else {
        this.previewTarget.style.removeProperty("--chip-color")
      }
      const name = this.hasNameTarget ? this.nameTarget.value.trim() : ""
      this.previewTarget.textContent = name || "Nova etiqueta"
    }
  }
}
