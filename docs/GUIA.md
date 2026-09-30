# Guia do projeto ToDo

Este guia explica para que serve cada ficheiro, como os pedidos atravessam a aplicação,
como fazer as alterações mais comuns, o que falta fazer e ideias que valem a pena.
As regras de estilo e os componentes visuais estão em [CONVENTIONS.md](CONVENTIONS.md).

---

## 1. Como funciona um pedido (visão geral)

```
Browser ──> config/routes.rb ──> Controller ──> Service (se houver vários passos) ──> Model ──> Base de dados
                                     │
                                     └──> View (.html.erb) + layout + CSS ──> HTML de volta ao browser
```

Exemplo, **concluir uma tarefa**:

1. O botão "Concluir" envia `PATCH /tasks/12/complete`.
2. `config/routes.rb` encaminha para `TasksController#complete`.
3. O controller procura a tarefa **só entre as do utilizador**: `Current.user.tasks.find(12)`
   (se for de outra pessoa dá 404).
4. Chama o serviço `Tasks::Complete`, que muda o estado, preenche `completed_at`,
   cria a próxima ocorrência se a tarefa for recorrente e escreve no histórico (`AuditLog`).
5. O modelo `Task` valida os dados e grava; o concern `CalendarSyncable` agenda a
   sincronização com o Google Calendar se estiver ligado.
6. O controller redireciona com uma mensagem ("flash") e a página é desenhada de novo.

Tarefas demoradas (sincronizar calendário, enviar lembretes) correm em **jobs**
(`app/jobs`) fora do pedido, para a página nunca ficar à espera de um serviço externo.

---

## 2. Estrutura de pastas e ficheiros

### 2.1 Base de dados — `db/`

| Ficheiro | Para que serve |
| --- | --- |
| `migrate/…_create_users.rb` | Tabela `users` (email, password cifrada, nome, avatar, objetivo, tema, fuso horário). |
| `migrate/…_create_sessions.rb` | Tabela `sessions`: uma linha por dispositivo com sessão iniciada (gerada pelo Rails). |
| `migrate/…_create_job_domain.rb` | `job_searches`, `job_filters`, `job_listings`, `job_applications`, `job_application_events`. |
| `migrate/…_create_tasks.rb` | `tasks` (com `parent_task_id` para subtarefas), `task_recurrences`, `tags`, `task_tags`, `reminders`, `links`. |
| `migrate/…_create_calendar_notifications_audit.rb` | `calendar_connections`, `calendar_events`, `notifications`, `audit_logs`. |
| `migrate/…_create_tarefas.rb` | **Antigo** (primeiro esboço). Não é usado; ver "O que falta fazer". |
| `schema.rb` | Fotografia do esquema atual, gerada automaticamente. Não editar à mão. |
| `seeds.rb` | Dados de demonstração (`demo@todo.pt` / `password123`). Pode correr várias vezes sem duplicar. |

**Regra:** para mudar a base de dados cria-se **sempre uma migration nova**
(`bin/rails g migration AddXToTasks x:string`), nunca se editam migrations antigas.

### 2.2 Modelos — `app/models/` (dados + regras)

| Ficheiro | O que representa | Regras importantes |
| --- | --- | --- |
| `user.rb` | Conta do utilizador. | Email único, password ≥ 8, tema (`light`/`dark`/`system`), fuso horário válido. Ao apagar, apaga tudo o que é dele. |
| `session.rb` / `current.rb` | Sessão iniciada / "quem está a usar agora" (`Current.user`). | Geradas pelo Rails 8. |
| `task.rb` | Tarefa **e** subtarefa (via `parent_task_id`). | Título obrigatório; prazo ≥ início; sem ciclos na hierarquia (máx. 5 níveis); pai e candidatura do mesmo dono; transições de estado; `completed_at` sincronizado com o estado; progresso das subtarefas. |
| `task_recurrence.rb` | Regra de repetição (diária/semanal/mensal/anual, intervalo, fim). | `next_time` calcula a próxima data. Só se cria **uma** ocorrência de cada vez. |
| `tag.rb` / `task_tag.rb` | Etiquetas e a ligação tarefa↔etiqueta. | Nome único por utilizador (sem distinguir maiúsculas); cor hexadecimal; nunca ligar etiqueta de outro utilizador. |
| `reminder.rb` | Lembrete de uma tarefa (na app ou email). | Tem de ser no futuro; sem duplicados; `claim!` garante que nunca é enviado duas vezes; guarda erros e tenta até 5 vezes. |
| `link.rb` | Link externo associado a tarefa ou candidatura. | Só `http(s)://`; o dono do link tem de ser o dono do registo. |
| `job_search.rb` | Pesquisa de emprego guardada (LinkedIn/Indeed/Outra). | `search_url` gera o link com filtros. |
| `job_filter.rb` | Filtro de uma pesquisa (localização, recência, tipo…). | Chaves permitidas por fonte; valores normalizados ("semana" → `week`). |
| `job_listing.rb` | Vaga encontrada. | URL normalizada (sem `utm_`, `www`, `/` final) para **não duplicar**. |
| `job_application.rb` | Candidatura a uma vaga. | Estados e transições explícitas (`TRANSITIONS`); guarda título/empresa mesmo que a vaga desapareça. |
| `job_application_event.rb` | Histórico da candidatura (enviada, entrevista, nota…). | Datas plausíveis. |
| `calendar_connection.rb` | Ligação à conta Google. | Tokens **cifrados** na BD; `inspect` nunca mostra tokens. |
| `calendar_event.rb` | Correspondência tarefa ↔ evento no Google. | Um evento por tarefa e ligação (evita duplicados). |
| `concerns/calendar_syncable.rb` | Incluído em `Task`: agenda a sincronização quando a tarefa muda. | Nunca rebenta a gravação da tarefa se o Google falhar. |
| `notification.rb` | Aviso dentro da app. | Lida/não lida. |
| `audit_log.rb` | Histórico de ações importantes. | `AuditLog.record(...)`; apaga automaticamente chaves sensíveis (token, password…). |
| `tarefa.rb` | **Antigo**, não usado. | — |

### 2.3 Controllers — `app/controllers/` (recebem o pedido e respondem)

| Ficheiro | Páginas / ações |
| --- | --- |
| `application_controller.rb` | Base de todos: exige login, aplica o fuso horário do utilizador, filtra browsers antigos. |
| `concerns/authentication.rb` | Login por cookie de sessão (gerado pelo Rails). |
| `sessions_controller.rb` | Entrar / sair (`/session/new`). |
| `registrations_controller.rb` | Criar conta (`/registration/new`). |
| `passwords_controller.rb` | Recuperar password por email. |
| `profiles_controller.rb` | Perfil, editar dados, tema, mudar password, eliminar conta, botão de tema do topo (`update_theme`). |
| `audit_logs_controller.rb` | Página "Histórico" (`/history`). |
| `dashboard_controller.rb` | Página inicial "Hoje" (`/`). |
| `tasks_controller.rb` | Lista com filtros, detalhe, criar/editar/apagar, concluir, reabrir, iniciar, cancelar, arquivar. |
| `task_recurrences_controller.rb` | Criar/alterar/remover a repetição de uma tarefa. |
| `reminders_controller.rb` | Adicionar/remover lembretes de uma tarefa. |
| `tags_controller.rb` | Gerir etiquetas. |
| `links_controller.rb` | Adicionar/remover links (em tarefas e candidaturas). |
| `job_searches_controller.rb` | Pesquisas de emprego; `run` abre o site externo com os filtros. |
| `job_filters_controller.rb` | Filtros de uma pesquisa. |
| `job_listings_controller.rb` | Vagas: lista, detalhe, adicionar manualmente, apagar. |
| `job_applications_controller.rb` | Candidaturas: kanban/lista, detalhe, mudar estado (`transition`), criar tarefa ligada. |
| `job_application_events_controller.rb` | Eventos do histórico de uma candidatura. |
| `calendar_controller.rb` | Vista de calendário mensal/semanal. |
| `calendar_connections_controller.rb` | Ligar/desligar Google, callback OAuth, "Sincronizar agora". |
| `notifications_controller.rb` | Notificações, marcar como lida(s). |

### 2.4 Serviços — `app/services/` (fluxos com vários passos)

Cada serviço tem um método `.call` e devolve um resultado (`success?`, `error`).

| Ficheiro | O que faz |
| --- | --- |
| `tasks/create.rb` | Cria tarefa/subtarefa, filtra etiquetas, cria lembrete inicial, regista no histórico. |
| `tasks/update.rb` | Grava o formulário de edição. |
| `tasks/change_status.rb` | Muda o estado respeitando as transições permitidas. |
| `tasks/complete.rb` | Conclui; se for recorrente cria a próxima ocorrência. Não mexe nas subtarefas. |
| `tasks/archive.rb` | Arquivar/restaurar (alternativa segura a apagar). |
| `tasks/filter.rb` | Toda a lógica de filtros, pesquisa, ordenação e paginação da lista de tarefas. |
| `tasks/owned_tag_ids.rb` | Deixa passar só etiquetas do próprio utilizador. |
| `tasks/result.rb`, `job_applications/result.rb` | Objetos de resultado dos serviços. |
| `reminders/dispatcher.rb` | Transforma lembretes vencidos em notificações/emails, sem duplicar. |
| `job_searches/sources.rb` + `sources/{base,linkedin,indeed,other}.rb` | "Adaptadores": sabem construir o URL de pesquisa de cada site. **Novo site = novo adaptador.** |
| `job_searches/runner.rb` | Executa uma pesquisa: gera URL, guarda `last_run_at`, histórico. |
| `job_listings/importer.rb` | Única porta de entrada de vagas; nunca duplica. |
| `job_applications/create.rb` | Cria candidatura (manual ou a partir de vaga) com o primeiro evento. |
| `job_applications/transition.rb` | Muda estado, cria evento, opcionalmente tarefa de follow-up/entrevista + lembrete. |
| `job_applications/create_task.rb` | "Criar tarefa" a partir de uma candidatura. |
| `calendar.rb` | Ponto de entrada do módulo; `Calendar.client` (trocado por um falso nos testes). |
| `calendar/connect.rb` / `disconnect.rb` | Guardar a ligação após OAuth / revogar e esquecer. |
| `calendar/token_refresher.rb` | Renova o token quando expira; se o Google recusar, marca erro. |
| `calendar/auth_failure.rb` | Marca a ligação com erro e avisa o utilizador uma vez. |
| `calendar/sync.rb` | Sincronização completa de uma ligação. |
| `calendar/task_sync.rb` | Sincroniza **uma** tarefa (idempotente; deteta conflitos). |
| `calendar/event_mapper.rb` | Converte uma tarefa em evento Google (datas, título, fuso). |
| `calendar/period.rb` / `agenda.rb` | Calcula o mês/semana visível e as tarefas de cada dia. |

### 2.5 Outras pastas de `app/`

| Pasta / ficheiro | Para que serve |
| --- | --- |
| `clients/google_calendar_client.rb` | Fala com a API da Google (OAuth + Calendar) usando só `Net::HTTP`. Erros tipados (`AuthError`, `NotFoundError`…). |
| `jobs/reminder_dispatch_job.rb` | A cada minuto: envia lembretes vencidos. |
| `jobs/due_task_notification_job.rb` | A cada hora: avisa de tarefas que vencem nas próximas 24h. |
| `jobs/calendar_sync_job.rb` | Sincronização completa com o Google (só repete erros de rede). |
| `jobs/calendar_task_sync_job.rb` / `calendar_event_delete_job.rb` | Sincronizar/apagar o evento de uma tarefa. |
| `mailers/notification_mailer.rb` | Email de lembrete (vistas em `views/notification_mailer`). |
| `mailers/passwords_mailer.rb` | Email de recuperação de password. |
| `presenters/dashboard_presenter.rb` | Prepara todos os dados da página "Hoje" (saudação, contadores, listas). |
| `helpers/application_helper.rb` | Funções usadas nas views: `icon`, `status_badge`, `relative_due`, `progress_bar`, botão de tema… |
| `helpers/*_helper.rb` | Rótulos em português e pequenas funções de cada área (tarefas, emprego, calendário…). |
| `javascript/controllers/*.js` | Comportamentos Stimulus: menu lateral, mensagens, tema, filtros automáticos de tarefas, kanban com arrastar-e-largar, formulário de filtros de emprego, copiar URL, pré-visualização de etiquetas. |
| `views/layouts/application.html.erb` | Moldura de todas as páginas: menu lateral, barra de topo (pesquisa, nova tarefa, tema, avatar, sair) ou painel de login. |
| `views/shared/` | Partes reutilizáveis: mensagens, erros de formulário, estado vazio. |
| `views/<área>/` | Páginas de cada área. Ficheiros com `_` no início são *partials* (pedaços reutilizados). |

### 2.6 Estilos — `app/assets/stylesheets/`

| Ficheiro | Conteúdo |
| --- | --- |
| `application.css` | **Design system**: cores (tokens), tipografia, layout, botões, cartões, formulários, badges, listas, kanban… |
| `tasks.css`, `dashboard.css`, `jobs.css`, `applications.css`, `calendar.css`, `tags.css`, `account.css` | Estilos específicos de cada área, sempre usando os tokens. |

**Cores e tema:** cada cor é definida uma vez como `light-dark(<claro>, <escuro>)` no topo de
`application.css`. O atributo `data-theme` do `<html>` escolhe:
`light` (sempre claro), `dark` (sempre escuro) ou `system` (segue o sistema operativo).
Para mudar uma cor da app inteira basta mudar o token.

### 2.7 Configuração — `config/`

| Ficheiro | Para que serve |
| --- | --- |
| `routes.rb` | Todos os URLs da app. |
| `application.rb` | Fuso horário por omissão (Lisboa), idioma `pt`, credenciais Google via variáveis de ambiente. |
| `database.yml` | SQLite em desenvolvimento/teste (`TEST_DATABASE` permite outra BD de teste). |
| `environments/development.rb`, `test.rb` | Chaves de cifra **só para desenvolvimento/teste**. |
| `environments/production.rb` | Em produção as chaves vêm das credenciais ou de `AR_ENCRYPTION_*`. |
| `locales/pt.yml` | Nomes dos modelos/campos em português (mensagens de erro, datas). |
| `recurring.yml` | Jobs periódicos (lembretes a cada minuto, prazos a cada hora). |

### 2.8 Testes — `test/`

`models/`, `controllers/`, `services/`, `jobs/`, `mailers/`, `clients/`: cerca de 500 testes.
`fixtures/users.yml` tem os utilizadores de teste (`users(:one)`, `users(:two)`);
os outros dados criam-se dentro de cada teste. `support/fake_google_calendar_client.rb`
simula o Google para os testes não usarem a rede.

Comandos: `bin/rails test` (testes), `bin/rubocop` (estilo), `bin/brakeman` (segurança).

---

## 3. Como fazer alterações comuns

**Adicionar um campo às tarefas (ex.: "estimativa em minutos")**
1. `bin/rails g migration AddEstimateToTasks estimate_minutes:integer` → `bin/rails db:migrate`
2. `task.rb`: validação (`validates :estimate_minutes, numericality: { greater_than: 0 }, allow_nil: true`).
3. `tasks_controller.rb`: acrescentar `:estimate_minutes` aos parâmetros permitidos.
4. `views/tasks/_form.html.erb`: campo no formulário; `show.html.erb`: mostrar o valor.
5. `config/locales/pt.yml`: nome do campo em português.
6. Um teste em `test/models/task_test.rb`.

**Mudar uma cor** → token em `application.css` (os dois valores de `light-dark`).

**Nova página** → rota em `routes.rb` → controller → view em `app/views/<nome>/` → link no menu
(`layouts/application.html.erb`, com `nav_link_to`).

**Novo site de emprego** → novo adaptador em `app/services/job_searches/sources/`, registá-lo em
`sources.rb`, acrescentar a fonte em `JobSearch::SOURCES`, `JobListing::SOURCES` e
`JobFilter::ALLOWED_KEYS`.

**Novo estado de candidatura** → `JobApplication::STATUSES`, `TRANSITIONS`, `STATUS_LABELS`,
estilo `badge--<estado>` em `application.css`.

---

## 4. O que falta fazer (em relação ao plano)

| Prioridade | Tarefa | Notas |
| --- | --- | --- |
| Alta | **Commit inicial no Git** | Nada está commitado ainda. |
| Alta | **Jobs em desenvolvimento** | Os lembretes automáticos só correm com `bin/jobs` num segundo terminal. Configurar o Solid Queue em dev (BD `queue` + plugin no Puma) para correr com `bin/dev`. |
| Alta | **Revisão de segurança** (fase 10) | Ativar Content Security Policy (`config/initializers/content_security_policy.rb`); rever o aviso do brakeman em `job_listings/show` (falso positivo — a URL é validada). |
| Média | **Remover o modelo antigo `Tarefa`** | Migration `drop_table :tarefas` + apagar `app/models/tarefa.rb`, `test/fixtures/tarefas.yml`, `test/models/tarefa_test.rb`. |
| Média | **Google Calendar real** | Criar projeto na Google Cloud, OAuth com redirect `…/calendar_connection/callback`, definir `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` e testar à mão. |
| Média | **PostgreSQL em produção** | Gem `pg`, `database.yml` de produção, `DATABASE_URL`. As migrations já são compatíveis. |
| Média | **Email em produção** | SMTP em `production.rb` + `MAILER_HOST`/`MAILER_FROM`. |
| Média | **Testes de sistema (browser)** | Capybara para os fluxos completos (criar tarefa, candidatura). Não há nenhum ainda. |
| Média | **CI** | Confirmar que o GitHub Actions corre `bin/rails db:test:prepare test`. |
| Baixa | **Deploy** | `config/deploy.yml` (Kamal) ainda tem os valores de exemplo. Backups da BD. |
| Baixa | **Ordenação manual** | A coluna `tasks.position` existe mas ainda não há arrastar-e-largar na lista. |

---

## 5. Coisas que o plano não previa e que valem a pena

**Procura de emprego**
- **Empresas e contactos** (`companies`, `contacts`): o mesmo recrutador/empresa aparece em várias
  candidaturas; permite notas por empresa e lembrar "a quem enviar follow-up".
- **Documentos por candidatura** (Active Storage): que versão do CV e carta foram enviadas.
- **Salário e modalidade** (remoto/híbrido/presencial) nas vagas e candidaturas, para filtrar e comparar.
- **Estatísticas**: funil (guardadas → enviadas → entrevistas → ofertas), taxa de resposta,
  tempo médio até resposta.
- **Lembrete automático de follow-up** se uma candidatura estiver em "enviada" há X dias sem eventos.

**Tarefas e produtividade**
- **Dependências entre tarefas** ("bloqueada por"), além de pai/filho.
- **Estimativa e tempo gasto** (ou um temporizador tipo Pomodoro).
- **Lixo com restauro**: hoje apagar é definitivo; um "apagado há 30 dias" evita acidentes.
- **Pesquisa global** (tarefas + vagas + candidaturas) na barra de topo.

**Calendário**
- **Feed ICS só de leitura** (`/calendar.ics?token=…`): qualquer calendário (Google, Apple, Outlook)
  subscreve sem OAuth. Muito mais simples do que a integração completa e útil já.
- **Webhooks do Google** (push) em vez de sincronizações periódicas.

**Conta, segurança e dados**
- **Confirmação de email** no registo e **2FA** opcional.
- **Exportar os meus dados** (JSON/CSV) — boa prática (RGPD) e serve de backup pessoal.
- **Ver e terminar sessões** noutros dispositivos: o perfil já mostra quantas existem; falta a lista
  (a tabela `sessions` guarda IP e browser) e um botão "terminar" por sessão.

**Experiência**
- **PWA** (instalar no telemóvel): o manifest já existe em `app/views/pwa`, basta ativar as rotas.
- **Notificações push** do browser para lembretes.
- **Atalhos de teclado** (ex.: `n` nova tarefa, `/` pesquisar).

**Coisas que eu lembrei**
- **Interatividade com outro utilizador** Ser possível colocar coisas para o outro utilizador ver, como candidaturas que ele poderia ver, tarefas para ele fazer, dar para aceitar ou nao essas coisas. 
- **Colocar Imagemns nos utilizadores** ainda nao da para eu colocar a minha foto de perfil
- **Mudar o estilo do site** o esquema base do site está muito "um site que o claude fez por mim" quero que seje mais original