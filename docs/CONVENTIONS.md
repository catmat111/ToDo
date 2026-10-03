# Convenções do projeto ToDo

Referência rápida para quem escreve código nesta app: regras e componentes visuais.
A organização do código (camadas, domínios, onde pôr cada coisa) está em [ARQUITETURA.md](ARQUITETURA.md).

## Stack

- Rails 8.1.4, Ruby 3.4 (via mise), Hotwire (Turbo + Stimulus), importmap, Propshaft.
- Base de dados: SQLite em desenvolvimento/teste. As migrations são portáveis para PostgreSQL
  (`json` em vez de `jsonb`, sem SQL específico). Ver README para mudar para PostgreSQL.
- Jobs: Active Job + Solid Queue. Tarefas recorrentes de sistema em `config/recurring.yml`.
- Autenticação: gerador nativo do Rails 8 (`User`, `Session`, `Current`, `Authentication`).
  O login usa a coluna `email_address` (convenção do gerador).

## Regras de domínio

- **Ownership sempre**: nunca `Model.find(params[:id])` para recursos privados.
  Usar `Current.user.tasks.find(params[:id])`, `Current.user.job_applications.find(...)`, etc.
  Registos de outro utilizador devem dar 404.
- **Controllers finos**: autenticar → encontrar via `Current.user` → chamar modelo/serviço → responder.
  Em falha de validação: `render :new/:edit, status: :unprocessable_entity`.
- **Strong parameters** em todos os controllers (`params.expect(task: [...])`).
- **Serviços** em `app/services/<dominio>/` para fluxos com vários passos (ex.: `Tasks::Complete`).
- **Clientes externos** em `app/clients/` (ex.: `GoogleCalendarClient`).
- **Auditoria**: ações importantes chamam `AuditLog.record("task.completed", resource: task, from: "pending")`.
  Nunca passar tokens/passwords (são redigidos, mas não os envies).
- **Datas**: guardadas em UTC; `ApplicationController` aplica `Time.use_zone(Current.user.time_zone)`.
  Em formulários usar `datetime_field`/`datetime-local`.
- **Estados**: enums de string explícitos (`Task::STATUSES`, `JobApplication::TRANSITIONS`). Nada de booleans soltos.

## UI (pt-PT)

Todo o texto visível em português de Portugal. Design system em camadas, em
`app/assets/stylesheets/` (`1-base/` tokens → `2-layout/` → `3-components/` → `4-pages/`);
estilos de uma só área vão para `4-pages/<área>.css` e usam apenas os tokens
(`var(--color-primary)`, …), nunca hex soltos.

Paleta: Terracotta `#9C5D3C` (primária) · Olive Green `#6E6B41` (acento) · Warm Cream `#D1C7B5`
(bordas/superfícies) · Mustard Gold `#B07E1E` (aviso/destaque) · Charcoal Brown `#382C23` (texto/cabeçalho).
Tema claro, escuro ou automático via `data-theme` no `<html>` (preferência `users.theme`);
cada cor é definida uma vez com `light-dark(claro, escuro)` em `1-base/tokens.css`.

### Estrutura típica de página

```erb
<% content_for :title, "Tarefas" %>
<div class="page-header">
  <div>
    <h1 class="page-header__title">Tarefas</h1>
    <p class="page-header__subtitle">12 pendentes</p>
  </div>
  <div class="page-header__actions">
    <%= link_to new_task_path, class: "btn btn--primary" do %><%= icon :plus %> Nova tarefa<% end %>
  </div>
</div>

<div class="card card--flush">
  <ul class="list">
    <li class="list__item">
      <div class="list__main">
        <%= link_to task.title, task, class: "list__title" %>
        <div class="list__meta"><%= status_badge(task.status) %> <%= relative_due(task.due_at) %></div>
      </div>
      <div class="list__actions">…</div>
    </li>
  </ul>
</div>
```

### Componentes disponíveis

| Classe | Uso |
| --- | --- |
| `page-header`, `__title`, `__subtitle`, `__actions`, `breadcrumb` | Cabeçalho de página |
| `card`, `card--flush`, `card--accent/olive/mustard`, `card__header`, `card__title`, `card__footer` | Blocos |
| `stat`, `stat--terracotta/olive/mustard/charcoal`, `stat__value`, `stat__label` | Números do dashboard |
| `btn`, `btn--primary/secondary/warning/outline/ghost/danger`, `btn--sm`, `btn--icon`, `btn--block` | Botões |
| `badge`, `badge--<status>` (pending, in-progress, completed, cancelled, saved, applied, interview, offer, rejected, withdrawn, error, synced, overdue, archived, type, priority-1..3) | Estados |
| `chip` (+ `--chip-color`) | Etiquetas |
| `form`, `form__row`, `form__actions`, `form__section`, `field`, `field__label`, `field__hint`, `field__error`, `check`, `check-group`, `filters` | Formulários |
| `list`, `list__item`, `list__main`, `list__title`, `list__meta`, `list__actions` | Listas |
| `table-wrap`, `table`, `dl` | Tabelas / detalhes |
| `progress` (helper `progress_bar`) | Progresso |
| `empty-state` (partial `shared/empty_state`) | Listas vazias |
| `tabs`, `tabs__link`, `is-active` | Separadores |
| `kanban`, `kanban__column`, `kanban__header`, `kanban__cards`, `kanban__card` | Candidaturas |
| `timeline`, `timeline__item`, `timeline__date` | Histórico |
| `grid grid--2/3`, `grid--sidebar`, `stack`, `cluster`, `spread`, `muted`, `small`, `sr-only` | Layout |

### Helpers

`icon(:name)` (IconsHelper) · `status_badge`, `priority_badge`, `tag_chip`, `progress_bar` (BadgesHelper) ·
`format_datetime`, `format_date`, `relative_due` (FormattingHelper) · `section_links`,
`unread_notifications_count` (NavigationHelper) · `theme_toggle_button` (ThemeHelper).
Partials: `shared/form_errors` (`record:`), `shared/empty_state` (`title:, body:, action:`), `shared/flash`.

Ícones disponíveis: home, tasks, calendar, briefcase, search, list, bell, settings, tag, plus, check,
clock, link, trash, edit, archive, external, user, logout, history, refresh, menu.

Links externos: `target: "_blank", rel: "noopener noreferrer"`.
Ações destrutivas: `button_to … method: :delete, form: { data: { turbo_confirm: "Tens a certeza?" } }`.

## Testes

- Minitest. Fixtures só para `users` (`users(:one)`, `users(:two)`, password `"password"`).
  Outros registos criam-se inline (`create_task`, `create_job_application` em `test_helper.rb`).
- Testes de integração: `sign_in_as(users(:one))`.
- Cada área tem testes de autorização: o utilizador B não vê nem altera dados de A (404).
- Correr: `bin/rails test`. Lint: `bin/rubocop`. Segurança: `bin/brakeman`.
