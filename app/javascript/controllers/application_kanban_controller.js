import { Controller } from "@hotwired/stimulus"

// Drag & drop on the applications kanban. Dropping a card on a column submits the same
// PATCH /applications/:id/transition the show page uses (Turbo follows the redirect),
// and only columns allowed by JobApplication::TRANSITIONS accept the card.
// Everything remains reachable without drag & drop from the application's page.
export default class extends Controller {
  static targets = [ "column", "card" ]

  cardTargetConnected(card) {
    card.addEventListener("dragstart", this.dragStart)
    card.addEventListener("dragend", this.dragEnd)
  }

  cardTargetDisconnected(card) {
    card.removeEventListener("dragstart", this.dragStart)
    card.removeEventListener("dragend", this.dragEnd)
  }

  columnTargetConnected(column) {
    column.addEventListener("dragover", this.dragOver)
    column.addEventListener("dragleave", this.dragLeave)
    column.addEventListener("drop", this.drop)
  }

  columnTargetDisconnected(column) {
    column.removeEventListener("dragover", this.dragOver)
    column.removeEventListener("dragleave", this.dragLeave)
    column.removeEventListener("drop", this.drop)
  }

  dragStart = (event) => {
    const card = event.currentTarget
    if (card.getAttribute("draggable") !== "true") return

    this.draggedCard = card
    card.classList.add("is-dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", card.dataset.title || "")

    const allowed = this.allowedFor(card)
    this.columnTargets.forEach((column) => {
      if (column.dataset.status === card.dataset.status) return
      column.classList.add(allowed.includes(column.dataset.status) ? "is-drop-allowed" : "is-drop-denied")
    })
  }

  dragEnd = () => {
    if (this.draggedCard) this.draggedCard.classList.remove("is-dragging")
    this.draggedCard = null
    this.columnTargets.forEach((column) => {
      column.classList.remove("is-drop-allowed", "is-drop-denied", "is-drop-target")
    })
  }

  dragOver = (event) => {
    if (!this.canDrop(event.currentTarget)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("is-drop-target")
  }

  dragLeave = (event) => {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      event.currentTarget.classList.remove("is-drop-target")
    }
  }

  drop = (event) => {
    const column = event.currentTarget
    const card = this.draggedCard
    if (!card || !this.canDrop(column)) return
    event.preventDefault()

    this.dragEnd()
    this.submitTransition(card, column)
  }

  // private

  allowedFor(card) {
    return (card.dataset.allowed || "").split(" ").filter(Boolean)
  }

  canDrop(column) {
    const card = this.draggedCard
    if (!card || column.dataset.status === card.dataset.status) return false
    return this.allowedFor(card).includes(column.dataset.status)
  }

  submitTransition(card, column) {
    const to = column.dataset.status
    const form = document.createElement("form")
    form.method = "post"
    form.action = card.dataset.url
    form.hidden = true

    this.appendField(form, "_method", "patch")
    this.appendField(form, "transition[to]", to)
    this.appendField(form, "return_to", "index")
    const token = document.querySelector("meta[name='csrf-token']")
    if (token) this.appendField(form, "authenticity_token", token.content)

    // Final states can't be undone: let Turbo ask for confirmation first.
    if (to === "rejected" || to === "withdrawn") {
      form.dataset.turboConfirm = `Marcar «${card.dataset.title}» como «${column.dataset.label}»? Este estado é final.`
    }

    this.element.appendChild(form)
    form.addEventListener("turbo:submit-start", () => card.classList.add("is-pending"))
    form.addEventListener("turbo:submit-end", () => {
      card.classList.remove("is-pending")
      form.remove()
    })
    form.requestSubmit()
  }

  appendField(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
}
