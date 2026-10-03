import { Controller } from "@hotwired/stimulus"

// Press "/" anywhere (outside a text field) to jump to the masthead search box.
export default class extends Controller {
  static targets = ["input"]

  focus(event) {
    const tag = event.target.tagName
    if (event.key !== "/" || event.target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(tag)) return
    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }
}
