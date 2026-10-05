// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Installable app (PWA): the service worker only adds the "Sem ligação" page.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker", { scope: "/" }).catch(() => {})
}
