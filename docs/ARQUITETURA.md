# Arquitetura do Tu Do

Como a aplicação está organizada, porquê, e onde pôr cada coisa nova.
Para o aspeto visual (componentes, cores, helpers de UI) ver [CONVENTIONS.md](CONVENTIONS.md);
para o que cada funcionalidade faz ver [GUIA.md](GUIA.md).

---

## 1. Princípios

1. **Um monólito Rails simples.** Sem API separada nem SPA: páginas HTML com Hotwire
   (Turbo + Stimulus). Menos peças, menos coisas a partir.
2. **Cada utilizador só vê o que é seu.** Todos os registos privados são carregados por
   `Current.user.<associação>.find(...)`. Outra pessoa → 404. Sem exceções.
3. **Integrações externas nunca bloqueiam o núcleo.** Google Calendar, Gmail e LinkedIn são
   módulos isolados; se falharem, as tarefas e candidaturas continuam a funcionar.
4. **Nada muda nas costas do utilizador.** Sugestões automáticas (respostas do Gmail, tarefas
   que podiam ser concluídas) são *sugeridas* e confirmadas, nunca aplicadas em silêncio.
5. **Trabalho lento vai para jobs.** Sincronizações, emails e lembretes correm em segundo plano
   (Solid Queue), nunca dentro do pedido HTTP.

---

## 2. O caminho de um pedido

```
routes.rb → Controller → (Service) → Model → base de dados
                 │
                 └→ View (+ Presenter / Helpers) → HTML (+ Turbo Streams)
```

| Camada | Pasta | Responsabilidade | Regra |
|---|---|---|---|
| Rotas | `config/routes.rb` | URLs, agrupados pela mesma ordem do menu | Só REST + ações membro claras (`complete`, `transition`…) |
| Controllers | `app/controllers` | Autenticar → encontrar via `Current.user` → chamar → responder | Finos. Sem regras de negócio |
| Services | `app/services/<domínio>/` | Fluxos com vários passos (criar + auditar + notificar…) | Um verbo por classe, `.call`, devolvem resultado com `success?` |
| Models | `app/models` | Dados, associações, validações, regras de um só registo | Sem chamadas externas |
| Concerns de modelo | `app/models/concerns` | Comportamento partilhado (`Compensation`, `CalendarSyncable`) | |
| Clients | `app/clients` | Falar com APIs externas (HTTP, OAuth, erros tipados) | Sem lógica de negócio |
| Jobs | `app/jobs` | Trabalho em segundo plano; recorrentes em `config/recurring.yml` | Idempotentes (correr 2× = mesmo resultado) |
| Presenters | `app/presenters` | Preparar dados de uma página complexa (Hoje) | |
| Helpers | `app/helpers` | Formatar e desenhar pedaços de UI | Ver §6 |
| Views | `app/views/<recurso>/` | HTML; `_nome.html.erb` = partial reutilizável | Sem consultas pesadas |
| Stimulus | `app/javascript/controllers` | Pequenos comportamentos no browser | Um ficheiro por comportamento |
| CSS | `app/assets/stylesheets` | Design system em camadas | Ver §5 |

---

## 3. Domínios

A aplicação divide-se em domínios. Cada um tem os seus modelos, serviços e páginas.

| Domínio | Modelos | Serviços | Integração externa | Menu |
|---|---|---|---|---|
| **Conta** | `User`, `Session`, `Current`, `AuditLog` | — | — | Avatar → Perfil, Histórico |
| **Tarefas** | `Task` (+ subtarefas via `parent_task_id`), `TaskRecurrence`, `TaskDependency`, `Tag`, `TaskTag`, `Reminder`, `Link` | `Tasks::*`, `Reminders::Dispatcher` | — | Tarefas |
| **Calendário** | `CalendarConnection`, `CalendarEvent` (+ `CalendarSyncable` em `Task`) | `Calendar::*` | `GoogleCalendarClient` | Calendário |
| **Emprego** | `JobSearch`, `JobFilter`, `JobListing`, `JobApplication`, `JobApplicationEvent`, `Company`, `Contact` (+ `Compensation`) | `JobSearches::*`, `JobListings::Importer`, `JobApplications::*` | Links LinkedIn/Indeed/ITjobs, CSV do LinkedIn | Emprego |
| **Respostas (Gmail)** | `MailboxConnection`, `EmailMessage` | `Inbox::*` | `GmailClient` | Emprego → Respostas |
| **Partilhas** | `Share` | `Shares::*` | — | Avatar → Partilhas |
| **Notificações** | `Notification` (tempo real via Turbo Streams) | — | Email (SMTP) | Sino |
| **Pesquisa** | — | `GlobalSearch` | — | Caixa no cabeçalho |

**Nomes do domínio "Respostas":** na interface chama-se *Respostas* (URL `/replies`); no código,
a ligação é `MailboxConnection`, cada email é `EmailMessage`, a lógica vive em `Inbox::*` e a API em
`GmailClient`.

### Clientes Google

```
GoogleClient            OAuth (autorizar, trocar código, renovar, revogar), HTTP, erros tipados
├── GoogleCalendarClient   eventos do calendário        (scope calendar.events)
└── GmailClient            etiquetas e emails, só leitura (scope gmail.readonly)
```

Erros (`GoogleClient::AuthError`, `NetworkError`, `NotFoundError`, `ConflictError`): os jobs só
repetem `NetworkError`; `AuthError` marca a ligação com erro e pede para voltar a ligar.

---

## 4. Trabalho em segundo plano

Com `bin/dev`, o Solid Queue corre dentro do servidor. Tarefas recorrentes (`config/recurring.yml`):

| Job | Quando | O que faz |
|---|---|---|
| `ReminderDispatchJob` | cada minuto | Lembretes vencidos → notificação (+ email) |
| `DueTaskNotificationJob` | cada hora | Aviso de tarefas que vencem nas próximas 24 h |
| `MailboxSyncJob` | cada hora | Lê respostas novas do Gmail → sugestões |
| `FollowUpReminderJob` | todos os dias às 9h | Candidaturas sem resposta há X dias → tarefa de follow-up |

Pontuais: `CalendarSyncJob`, `CalendarTaskSyncJob`, `CalendarEventDeleteJob`.

---

## 5. CSS — camadas por ordem de carregamento

O Rails carrega todos os `.css` de `app/assets/stylesheets` por ordem alfabética do caminho.
As pastas numeradas tornam essa ordem explícita: **cada camada pode usar as anteriores**.

```
1-base/        tokens.css (cores light-dark, letras, espaços), elements.css, utilities.css
2-layout/      masthead.css, auth.css, page-header.css
3-components/  badges, buttons, cards, empty-state, flash, forms, kanban, lists,
               progress, tabs, timeline, toasts
4-pages/       um ficheiro por área: tasks, home, jobs, applications, calendar, …
```

Regras:
- **Cores só por tokens** (`var(--color-primary)`, `var(--terracotta)`…). Mudar uma cor = mudar
  o token em `1-base/tokens.css`.
- **Uma regra por coisa.** Não redefinir um componente noutro ficheiro; se uma página precisa de
  uma variação, cria um modificador (`.card--olive`) ou uma classe própria da página (`.home-task`).
- Estilos de uma só página vão para `4-pages/<página>.css`.

---

## 6. Helpers

| Helper | Conteúdo |
|---|---|
| `IconsHelper` | `icon(:nome)` — ícones SVG |
| `NavigationHelper` | Secções do menu e segunda linha (`SECTIONS`, `section_links`) |
| `BadgesHelper` | `status_badge`, `priority_badge`, `tag_chip`, `progress_bar` |
| `FormattingHelper` | `format_datetime`, `format_date`, `relative_due` (prazo às 23:59 = "dia inteiro") |
| `ThemeHelper` | Botão de tema, `theme_attribute` |
| `<área>_helper.rb` | Rótulos e pequenos pedaços de UI de uma área (tasks, calendar, job_*…) |

---

## 7. Segurança (resumo)

- Autenticação nativa do Rails 8; sessões expiram após 30 dias sem uso; cookie `httponly`,
  `same_site: lax`, `secure` em produção.
- Autorização por *scoping* (`Current.user.…`); testes em `test/integration/security_test.rb`.
- Tokens OAuth cifrados (Active Record Encryption); nunca em logs nem no browser.
- CSP, Permissions-Policy, HTTPS forçado e proteção do cabeçalho `Host` em produção.
- Limites de tentativas em login, registo, recuperação/mudança de password, partilhas e importação.

---

## 8. Ambientes

| | Desenvolvimento | Teste | Produção |
|---|---|---|---|
| Base de dados | SQLite (+ queue e cable em SQLite) | SQLite (ou PostgreSQL via `DATABASE_URL`) | PostgreSQL (`DATABASE_URL`); cache/queue/cable em SQLite |
| Jobs | Solid Queue dentro do `bin/dev` | adaptador de teste | Solid Queue dentro do Puma |
| Email | ficheiros em `tmp/mails/` ou SMTP se definido | guardados em memória | SMTP |
| Publicação | — | GitHub Actions (SQLite + PostgreSQL) | Kamal (`config/deploy.yml`) |

---

## 9. Onde pôr uma coisa nova

| Quero… | Faço… |
|---|---|
| Um campo novo | Migration → modelo (validação) → parâmetros permitidos no controller → formulário/página → `config/locales/pt.yml` → teste |
| Uma página nova | Rota → controller (dados via `Current.user`) → view → link em `NavigationHelper#section_links` → CSS em `4-pages/` |
| Um fluxo com vários passos | Classe em `app/services/<domínio>/` com `.call`, chamada pelo controller |
| Falar com uma API nova | Cliente em `app/clients/` (herdar de `GoogleClient` se for Google) + serviço que o usa |
| Algo periódico | Job em `app/jobs/` + entrada em `config/recurring.yml` (dev e produção) |
| Uma cor/estilo global | Token em `1-base/tokens.css` ou componente em `3-components/` |
