import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a field changes (e.g. the status menu on the list).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
