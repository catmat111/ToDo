import { Controller } from "@hotwired/stimulus"

// Applies the task list filters as soon as a select or checkbox changes.
// The search box keeps the normal behaviour (Enter submits) so typing never loses focus.
export default class extends Controller {
  submit(event) {
    if (event?.target?.type === "search") return
    this.element.requestSubmit()
  }
}
