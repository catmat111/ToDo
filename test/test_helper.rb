ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # Only users are fixtures; build other records inline so slices stay independent.
    fixtures :all

    # Small builders shared by every test file.
    def create_task(user = users(:one), **attrs)
      user.tasks.create!({ title: "Tarefa #{SecureRandom.hex(3)}" }.merge(attrs))
    end

    def create_job_application(user = users(:one), **attrs)
      user.job_applications.create!({ title: "Vaga #{SecureRandom.hex(3)}", company_name: "ACME" }.merge(attrs))
    end
  end
end
