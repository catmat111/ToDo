# Routes, grouped like the masthead: Hoje · Tarefas · Calendário · Emprego · Conta.
# Every private resource is loaded through Current.user in its controller.
Rails.application.routes.draw do
  # --- Hoje & global search ---------------------------------------------------
  root "dashboard#show"
  resource :search, only: :show

  # --- Account: sign in/up, password reset, profile, history -------------------
  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :profile, only: %i[show edit update destroy] do
    get :password, on: :member, action: :edit_password
    patch :password, on: :member, action: :update_password
    patch :theme, on: :member, action: :update_theme
  end
  resources :audit_logs, only: :index, path: "history"

  # --- Tarefas -------------------------------------------------------------------
  resources :tasks do
    member do
      patch :start
      patch :complete
      patch :reopen
      patch :cancel
      patch :archive
      patch :unarchive
    end
    resources :reminders, only: %i[create destroy]
    resource :recurrence, only: %i[create update destroy], controller: "task_recurrences"
    resources :dependencies, only: %i[create destroy], controller: "task_dependencies", as: :dependencies
  end
  resources :tags, except: :show
  resources :links, only: %i[create destroy] # on tasks and applications

  # --- Calendário (+ Google Calendar sync) ----------------------------------------
  resource :calendar, only: :show, controller: "calendar"
  resource :calendar_connection, only: %i[show create destroy] do
    get :callback
    post :sync
  end

  # --- Emprego ---------------------------------------------------------------------
  # Fixed paths under /applications come before resources :job_applications so
  # "stats" / "import" are never read as an application id.
  get "applications/stats", to: "application_stats#show", as: :application_stats
  resource :linkedin_import, only: %i[new create], path: "applications/import"
  resources :job_applications, path: "applications" do
    member do
      patch :transition
      post :create_task
    end
    resources :job_application_events, only: %i[create destroy], path: "events"
  end
  resources :job_listings, only: %i[index show new create destroy]
  resources :job_searches do
    member { post :run }
    resources :job_filters, only: %i[create update destroy]
  end
  resources :companies
  resources :contacts, except: :show do
    member { post :follow_up }
  end
  # Replies from companies, read (read-only) from one Gmail label.
  resources :email_messages, only: :index, path: "replies" do
    member do
      patch :confirm
      patch :ignore
    end
  end
  resource :mailbox_connection, only: %i[show create update destroy] do
    get :callback
    post :sync
  end

  # --- Partilhas & notificações ------------------------------------------------------
  resources :shares, only: %i[index create destroy] do
    member do
      patch :accept
      patch :decline
    end
  end
  resources :notifications, only: :index do
    member { patch :read }
    collection { patch :read_all }
  end

  # --- PWA: installable app (manifest + service worker with an offline page) ---------
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "up" => "rails/health#show", as: :rails_health_check
end
