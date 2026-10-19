import { Controller } from "@hotwired/stimulus"

// Selection mode for the task list: shows a checkbox per row and a bar to delete
// the selected tasks (or all tasks matching the current filters).
export default class extends Controller {
  static targets = [ "item", "bar", "start", "all", "count", "deleteSelected" ]

  start() {
    this.element.classList.add("is-selecting")
    this.barTarget.hidden = false
    this.startTarget.hidden = true
  }

  cancel() {
    this.element.classList.remove("is-selecting")
    this.barTarget.hidden = true
    this.startTarget.hidden = false
    this.itemTargets.forEach((box) => { box.checked = false })
    this.update()
  }

  toggleAll() {
    this.itemTargets.forEach((box) => { box.checked = this.allTarget.checked })
    this.update()
  }

  update() {
    const selected = this.itemTargets.filter((box) => box.checked).length
    this.countTarget.textContent = selected === 1 ? "1 selecionada" : `${selected} selecionadas`
    this.deleteSelectedTarget.disabled = selected === 0
    this.deleteSelectedTarget.dataset.turboConfirm =
      `Eliminar ${selected === 1 ? "1 tarefa" : `${selected} tarefas`}? Esta ação não pode ser desfeita.`
    this.allTarget.checked = selected > 0 && selected === this.itemTargets.length
  }
}
