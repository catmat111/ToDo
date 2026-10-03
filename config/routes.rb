Rails.application.routes.draw do
  root "dashboard#show"
  resource :search, only: :show # global search (masthead)

  # Identity
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  resource :profile, only: %i[show edit update destroy] do
    get :password, on: :member, action: :edit_password
    patch :password, on: :member, action: :update_password
    patch :theme, on: :member, action: :update_theme
  end
  resources :audit_logs, only: :index, path: "history"

  # Productivity
  resources :tasks do
    resources :reminders, only: %i[create destroy]
    resource :recurrence, only: %i[create update destroy], controller: "task_recurrences"
    resources :dependencies, only: %i[create destroy], controller: "task_dependencies", as: :dependencies
    member do
      patch :complete
      patch :reopen
      patch :start
      patch :cancel
      patch :archive
      patch :unarchive
    end
  end
  resources :tags, except: :show
  resources :links, only: %i[create destroy]

  # Job search
  resources :job_searches do
    resources :job_filters, only: %i[create update destroy]
    member { post :run }
  end
  resources :job_listings, only: %i[index show new create destroy]
  # Before the resources below, so "stats" is not taken as an application id.
  get "applications/stats", to: "application_stats#show", as: :application_stats
  resources :job_applications, path: "applications" do
    resources :job_application_events, only: %i[create destroy], path: "events"
    member do
      patch :transition
      post :create_task
    end
  end

  # Calendar
  resource :calendar, only: :show, controller: "calendar"
  resource :calendar_connection, only: %i[show create destroy] do
    get :callback
    post :sync
  end

  resource :linkedin_import, only: %i[new create], path: "applications/import"
  # Gmail (read-only): replies from companies → suggested status changes
  resource :mailbox_connection, only: %i[show create update destroy] do
    get :callback
    post :sync
  end
  resources :email_messages, only: :index, path: "replies" do
    member do
      patch :confirm
      patch :ignore
    end
  end
  resources :companies
  resources :contacts, except: :show do
    member { post :follow_up }
  end

  # Sharing with other users
  resources :shares, only: %i[index create destroy] do
    member do
      patch :accept
      patch :decline
    end
  end

  # Notifications
  resources :notifications, only: :index do
    member { patch :read }
    collection { patch :read_all }
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
