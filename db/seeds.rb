# Dados de demonstração para o Tu Do.
#
#   bin/rails db:seed                          # desenvolvimento
#   RAILS_ENV=test bin/rails db:seed:replant   # CI
#
# Idempotente: pode ser executado várias vezes seguidas sem duplicar registos
# (cada registo é procurado por uma chave estável e depois atualizado).
# Em produção só corre com SEED_DEMO=1, para não criar uma conta com password conhecida.

if Rails.env.production? && ENV["SEED_DEMO"].blank?
  puts "Seeds de demonstração ignorados em produção (define SEED_DEMO=1 para os carregar)."
  return
end

module DemoSeeds
  module_function

  # Finds by +find_by+, assigns +attrs+ and saves only when something changed.
  def upsert!(scope, find_by, attrs = {})
    record = scope.find_or_initialize_by(find_by)
    record.assign_attributes(attrs)
    record.save! if record.new_record? || record.changed?
    record
  end

  # A time on +days+ from today, in the app's time zone (Europe/Lisbon).
  def at(days, hour, min = 0)
    (Time.zone.today + days).in_time_zone.change(hour: hour, min: min)
  end

  # Reminders must be created in the future; keep the one already there on reruns.
  def ensure_reminder!(task, remind_at)
    return if task.reminders.where(sent_at: nil).exists? || !task.open?
    remind_at = (Time.current + 1.hour).beginning_of_hour if remind_at <= Time.current
    task.reminders.create!(remind_at: remind_at, channel: "in_app")
  end
end

Time.use_zone("Europe/Lisbon") do
  ActiveRecord::Base.transaction do
    # ---------------------------------------------------------------- Utilizadora
    user = User.find_or_initialize_by(email_address: "demo@todo.pt")
    user.assign_attributes(
      name: "Catarina Demo",
      objective: "Terminar o curso com boas notas, conseguir o primeiro emprego como programadora júnior " \
                 "e manter uma rotina saudável pelo caminho.",
      theme: user.theme.presence || "light",
      timezone: "Europe/Lisbon"
    )
    user.password = "password123" if user.new_record? || !user.authenticate("password123")
    user.save!

    # -------------------------------------------------------------------- Etiquetas
    tags = {
      universidade: [ "Universidade", "#9C5D3C" ],
      emprego: [ "Emprego", "#6E6B41" ],
      casa: [ "Casa", "#B07E1E" ],
      saude: [ "Saúde", "#8A7F6A" ],
      pessoal: [ "Projeto pessoal", "#B5835A" ]
    }.transform_values do |(name, color)|
      DemoSeeds.upsert!(user.tags, { name: name }, color: color)
    end

    # ------------------------------------------------------------- Pesquisas de emprego
    linkedin = DemoSeeds.upsert!(user.job_searches, { name: "Júnior Software Portugal" },
                                 source: "linkedin", query: "junior software engineer", active: true,
                                 last_run_at: DemoSeeds.at(-1, 9))
    { "location" => "Portugal", "recency" => "week", "experience" => "entry", "remote" => "hybrid" }.each do |key, value|
      DemoSeeds.upsert!(linkedin.job_filters, { key: key }, value: value, operator: "equals")
    end

    indeed = DemoSeeds.upsert!(user.job_searches, { name: "Ruby on Rails em Lisboa" },
                               source: "indeed", query: "ruby on rails", active: true,
                               last_run_at: DemoSeeds.at(-2, 18, 30))
    { "location" => "Lisboa", "radius" => "25", "job_type" => "full_time", "recency" => "2weeks" }.each do |key, value|
      DemoSeeds.upsert!(indeed.job_filters, { key: key }, value: value, operator: "equals")
    end

    # ------------------------------------------------------------------------ Vagas
    listing_data = [
      { key: :lusitania, search: linkedin, source: "linkedin", external_id: "4012345678",
        url: "https://www.linkedin.com/jobs/view/4012345678", title: "Programador(a) Júnior Ruby on Rails",
        company_name: "Lusitânia Tech", location: "Lisboa (híbrido)", published_at: DemoSeeds.at(-16, 10),
        description: "Equipa de produto a construir uma plataforma de reservas em Rails 8 com Hotwire." },
      { key: :atlantico, search: linkedin, source: "linkedin", external_id: "4012349876",
        url: "https://www.linkedin.com/jobs/view/4012349876", title: "Software Engineer (Graduate)",
        company_name: "Atlântico Software", location: "Porto", published_at: DemoSeeds.at(-3, 9),
        description: "Programa de graduados com mentoria e rotação por equipas de backend e frontend." },
      { key: :mondego, search: linkedin, source: "linkedin", external_id: "4012351111",
        url: "https://www.linkedin.com/jobs/view/4012351111", title: "Backend Developer Júnior",
        company_name: "Mondego Data", location: "Coimbra (remoto)", published_at: DemoSeeds.at(-1, 15),
        description: "APIs em Ruby e PostgreSQL para uma plataforma de análise de dados." },
      { key: :douro, search: indeed, source: "indeed", external_id: "a1b2c3d4e5f60718",
        url: "https://pt.indeed.com/viewjob?jk=a1b2c3d4e5f60718", title: "Frontend Developer",
        company_name: "Douro Digital", location: "Lisboa", published_at: DemoSeeds.at(-8, 11),
        description: "Interfaces acessíveis com Stimulus e Turbo numa agência de produto." },
      { key: :tejo, search: indeed, source: "indeed", external_id: "f9e8d7c6b5a40312",
        url: "https://pt.indeed.com/viewjob?jk=f9e8d7c6b5a40312", title: "Estágio em Engenharia de Software",
        company_name: "Tejo Labs", location: "Oeiras", published_at: DemoSeeds.at(-35, 10),
        description: "Estágio profissional de 9 meses numa equipa de plataformas internas." }
    ]
    listings = listing_data.to_h do |data|
      attrs = data.except(:key, :search, :source, :external_id).merge(job_search: data[:search],
                                                                        discovered_at: data[:published_at] + 2.hours)
      [ data[:key], DemoSeeds.upsert!(user.job_listings, { source: data[:source], external_id: data[:external_id] }, attrs) ]
    end

    # ---------------------------------------------------------------- Candidaturas
    application_data = [
      { key: :lusitania, status: "interview", applied_at: DemoSeeds.at(-10, 21),
        notes: "Primeira entrevista correu bem. Perguntaram sobre testes e Active Record.",
        events: [ [ "saved", -14, 10, nil ], [ "applied", -10, 21, "Candidatura enviada pelo LinkedIn com carta de apresentação." ],
                  [ "interview", -3, 11, "Entrevista com RH (30 min). Próxima fase: entrevista técnica." ] ] },
      { key: :atlantico, status: "saved", applied_at: nil,
        notes: "Pedir a alguém da equipa para rever o CV antes de enviar.",
        events: [ [ "saved", -1, 18, nil ] ] },
      { key: :douro, status: "applied", applied_at: DemoSeeds.at(-5, 14),
        notes: "Portefólio enviado em anexo.",
        events: [ [ "saved", -6, 9, nil ], [ "applied", -5, 14, nil ], [ "follow_up", -1, 10, "Email de seguimento enviado ao recrutador." ] ] },
      { key: :tejo, status: "rejected", applied_at: DemoSeeds.at(-28, 16),
        notes: "Feedback: procuravam alguém com mais experiência em Java.",
        events: [ [ "saved", -30, 12, nil ], [ "applied", -28, 16, nil ], [ "rejected", -12, 9, "Resposta por email." ] ] }
    ]
    applications = application_data.to_h do |data|
      listing = listings.fetch(data[:key])
      application = DemoSeeds.upsert!(user.job_applications, { job_listing: listing },
                                      title: listing.title, company_name: listing.company_name,
                                      status: data[:status], applied_at: data[:applied_at], notes: data[:notes])
      data[:events].each do |event_type, days, hour, notes|
        DemoSeeds.upsert!(application.job_application_events, { event_type: event_type },
                          occurred_at: DemoSeeds.at(days, hour), notes: notes)
      end
      [ data[:key], application ]
    end

    # ------------------------------------------------------------------------ Tarefas
    task = ->(title, tag_keys: [], **attrs) do
      record = DemoSeeds.upsert!(user.tasks, { title: title, parent_task_id: attrs.delete(:parent_task)&.id }, attrs)
      record.tags = tag_keys.map { |key| tags.fetch(key) }
      record
    end

    relatorio = task.("Entregar relatório de Sistemas Distribuídos",
                      task_type: "delivery", status: "in_progress", priority: 3,
                      starts_at: DemoSeeds.at(-4, 9), due_at: DemoSeeds.at(0, 23, 59),
                      description: "Relatório final do projeto de grupo (máx. 12 páginas) + código no repositório.",
                      tag_keys: %i[universidade])
    renda = task.("Pagar a renda", task_type: "routine", status: "pending", priority: 2,
                  due_at: DemoSeeds.at(-1, 18), tag_keys: %i[casa])
    ginasio = task.("Treino de força no ginásio", task_type: "routine", status: "pending", priority: 1,
                    starts_at: DemoSeeds.at(0, 19), due_at: DemoSeeds.at(0, 20, 30), tag_keys: %i[saude])
    exame = task.("Estudar para o exame de Bases de Dados", task_type: "exam", status: "pending", priority: 2,
                  starts_at: DemoSeeds.at(5, 9, 30), due_at: DemoSeeds.at(5, 12),
                  description: "Normalização, índices, transações e SQL avançado. Rever os exames de 2024 e 2025.",
                  tag_keys: %i[universidade])
    entrevista = task.("Preparar entrevista técnica na Lusitânia Tech", task_type: "job", status: "pending", priority: 3,
                       due_at: DemoSeeds.at(2, 10), job_application: applications[:lusitania],
                       description: "Rever Active Record, testes com Minitest e o projeto do portefólio.",
                       tag_keys: %i[emprego])
    candidatura = task.("Enviar candidatura à Atlântico Software", task_type: "job", status: "pending", priority: 1,
                        due_at: DemoSeeds.at(1, 12), job_application: applications[:atlantico], tag_keys: %i[emprego])
    revisao = task.("Revisão semanal", task_type: "routine", status: "pending", priority: 1,
                    due_at: DemoSeeds.at((5 - Time.zone.today.wday) % 7, 18),
                    description: "Rever tarefas da semana, arquivar o que ficou feito e planear a próxima.",
                    tag_keys: %i[pessoal])
    task.("Marcar consulta no dentista", task_type: "other", status: "pending", priority: 0, tag_keys: %i[saude])
    task.("Ler o capítulo 4 de Clean Architecture", task_type: "other", status: "completed", priority: 0,
          due_at: DemoSeeds.at(-1, 22), tag_keys: %i[pessoal])
    task.("Comprar bilhetes para o concerto", task_type: "other", status: "cancelled", priority: 0,
          due_at: DemoSeeds.at(-3, 20), tag_keys: %i[casa])

    portefolio = task.("Portefólio pessoal", task_type: "project", status: "in_progress", priority: 2,
                       starts_at: DemoSeeds.at(-7, 9), due_at: DemoSeeds.at(14, 18),
                       description: "Site simples com projetos, CV e contactos.", tag_keys: %i[pessoal emprego])
    [
      [ "Escolher template e paleta de cores", "completed", nil, 1 ],
      [ "Escrever a secção “Sobre mim”", "completed", nil, 2 ],
      [ "Publicar no GitHub Pages", "pending", DemoSeeds.at(10, 18), 3 ]
    ].each do |title, status, due_at, position|
      task.(title, parent_task: portefolio, task_type: "project", status: status, due_at: due_at, position: position,
                   tag_keys: %i[pessoal])
    end

    # Recorrência semanal (gera apenas a próxima ocorrência quando a atual é concluída).
    DemoSeeds.upsert!(TaskRecurrence, { task_id: revisao.id }, frequency: "weekly", interval: 1)
    DemoSeeds.upsert!(TaskRecurrence, { task_id: ginasio.id }, frequency: "daily", interval: 2,
                                                               ends_at: DemoSeeds.at(60, 23))

    # --------------------------------------------------------------------- Lembretes
    DemoSeeds.ensure_reminder!(relatorio, DemoSeeds.at(0, 20))
    DemoSeeds.ensure_reminder!(exame, DemoSeeds.at(4, 20))
    DemoSeeds.ensure_reminder!(entrevista, DemoSeeds.at(1, 19))
    DemoSeeds.ensure_reminder!(candidatura, DemoSeeds.at(1, 9))

    # ------------------------------------------------------------------------- Links
    [
      [ relatorio, "https://github.com/", "Repositório do grupo" ],
      [ relatorio, "https://www.overleaf.com/", "Relatório (Overleaf)" ],
      [ exame, "https://www.postgresql.org/docs/current/indexes.html", "Documentação de índices" ],
      [ portefolio, "https://pages.github.com/", "GitHub Pages" ],
      [ entrevista, "https://guides.rubyonrails.org/active_record_querying.html", "Rails Guides — Active Record" ],
      [ applications[:lusitania], listings[:lusitania].url, "Anúncio no LinkedIn" ],
      [ applications[:douro], "https://www.example.com/portefolio.pdf", "Portefólio enviado" ]
    ].each do |linkable, url, label|
      DemoSeeds.upsert!(user.links, { linkable_type: linkable.class.name, linkable_id: linkable.id, url: url }, label: label)
    end

    # ----------------------------------------------------------------- Notificações
    [
      { title: "Bem-vinda ao Tu Do, Catarina!", notification_type: "system", read_at: DemoSeeds.at(-7, 10),
        body: "Começa por criar etiquetas e as tarefas desta semana." },
      { title: "Prazo hoje: Entregar relatório de Sistemas Distribuídos", notification_type: "task_due",
        notifiable: relatorio, body: "Entrega até às 23:59." },
      { title: "Tarefa em atraso: Pagar a renda", notification_type: "task_due", notifiable: renda,
        body: "O prazo terminou ontem às 18:00." },
      { title: "Entrevista na Lusitânia Tech", notification_type: "application", notifiable: applications[:lusitania],
        body: "A candidatura avançou para entrevista. Prepara a entrevista técnica." },
      { title: "Candidatura rejeitada: Tejo Labs", notification_type: "application", notifiable: applications[:tejo],
        read_at: DemoSeeds.at(-12, 12), body: "Guarda o feedback para as próximas candidaturas." }
    ].each do |attrs|
      DemoSeeds.upsert!(user.notifications, { title: attrs[:title] }, attrs.except(:title).reverse_merge(read_at: nil))
    end

    # -------------------------------------------------------------- Histórico (auditoria)
    [
      [ "user.registered", user, {} ],
      [ "tag.created", tags[:universidade], { name: "Universidade" } ],
      [ "task.created", relatorio, { title: relatorio.title } ],
      [ "task.created", portefolio, { title: portefolio.title } ],
      [ "job_search.created", linkedin, { name: linkedin.name } ],
      [ "job_application.created", applications[:lusitania], { title: applications[:lusitania].title } ],
      [ "job_application.status_changed", applications[:lusitania], { from: "applied", to: "interview" } ],
      [ "job_application.status_changed", applications[:tejo], { from: "applied", to: "rejected" } ]
    ].each do |action, resource, metadata|
      AuditLog.find_or_create_by!(user: user, action: action, resource_type: resource.class.name, resource_id: resource.id) do |log|
        log.metadata = metadata
      end
    end

    puts "Dados de demonstração prontos: #{user.email_address} / password123 " \
         "(#{user.tasks.count} tarefas, #{user.tags.count} etiquetas, #{user.job_applications.count} candidaturas)."
  end
end
