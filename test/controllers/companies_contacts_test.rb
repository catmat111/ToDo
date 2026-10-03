require "test_helper"

class CompaniesContactsTest < ActionDispatch::IntegrationTest
  setup do
    @ana = users(:one)
    sign_in_as @ana
  end

  test "an application's company name links it to a company, reusing it case-insensitively" do
    first = create_job_application(@ana, company_name: "ACME")
    second = create_job_application(@ana, company_name: "acme")
    assert_equal first.company, second.company
    assert_equal 1, @ana.companies.count
  end

  test "company pages are private" do
    company = users(:two).companies.create!(name: "Outra")
    get company_path(company)
    assert_response :not_found
  end

  test "creating a contact ignores another user's company" do
    other = users(:two).companies.create!(name: "Outra")
    post contacts_path, params: { contact: { name: "Rita", company_id: other.id } }
    assert_nil @ana.contacts.last.company
  end

  test "an application can't use another user's contact" do
    application = create_job_application(@ana)
    contact = users(:two).contacts.create!(name: "Rui")
    patch job_application_path(application), params: { job_application: { contact_id: contact.id } }
    assert_nil application.reload.contact
  end

  test "follow-up creates a task linked to the application" do
    application = create_job_application(@ana)
    contact = @ana.contacts.create!(name: "Rita Sousa", email: "rita@acme.pt")
    assert_difference -> { @ana.tasks.count } => 1 do
      post follow_up_contact_path(contact, job_application_id: application.id)
    end
    task = @ana.tasks.last
    assert_match "Rita Sousa", task.title
    assert_equal application, task.job_application
    assert_redirected_to edit_task_path(task)
  end
end
