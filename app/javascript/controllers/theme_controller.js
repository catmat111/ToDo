import { Controller } from "@hotwired/stimulus"

// Turbo swaps <body> but never touches <html> attributes, so after a Turbo visit
// (e.g. logging out) the previous user's theme would linger. This keeps
// <html data-theme> in sync with the theme of the page that was rendered.
//
//   <div data-controller="theme" data-theme-name-value="light" hidden></div>
export default class extends Controller {
  static values = { name: String }

  connect() {
    if (this.nameValue) document.documentElement.dataset.theme = this.nameValue
  }
}
