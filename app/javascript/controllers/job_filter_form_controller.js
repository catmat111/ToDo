import { Controller } from "@hotwired/stimulus"

// Adapts the job filter form to the selected key: points the value input at the
// matching <datalist> of suggestions and restricts structured keys to "Igual".
export default class extends Controller {
  static targets = [ "key", "operator", "value" ]
  static values = { prefix: String, freeText: Array }

  connect() {
    this.update({ initial: true })
  }

  update(event) {
    if (!this.hasKeyTarget || !this.hasValueTarget) return

    const key = this.keyTarget.value
    const listId = `${this.prefixValue}-${key}`
    const list = document.getElementById(listId)
    const hasSuggestions = list && list.options.length > 0

    if (hasSuggestions) {
      this.valueTarget.setAttribute("list", listId)
    } else {
      this.valueTarget.removeAttribute("list")
    }

    const initial = event && event.initial
    if (!initial) this.valueTarget.value = ""
    this.valueTarget.placeholder = hasSuggestions ? "Escolhe uma opção" : "Escreve um valor"

    this.restrictOperators(this.freeTextValue.includes(key))
  }

  restrictOperators(freeText) {
    if (!this.hasOperatorTarget) return

    Array.from(this.operatorTarget.options).forEach((option) => {
      option.disabled = !freeText && option.value !== "equals"
    })
    if (!freeText) this.operatorTarget.value = "equals"
  }
}
