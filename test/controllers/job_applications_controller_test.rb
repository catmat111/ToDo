require "test_helper"

class JobApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @application = create_job_application(@user, title: "Programador Rails", company_name: "Alfa")
    @application.job_application_events.create!(event_type: "saved", occurred_at: 1.day.ago, notes: "Vi no LinkedIn")
  end

  test "requires authentication" do
    sign_out
    get job_applications_url
    assert_redirected_to new_session_url
  end

  # ---------- index ----------

  test "index shows the kanban with every column and the user's applications only" do
    create_job_application(@user, title: "Designer", status: "interview")
    create_job_application(users(:two), title: "Segredo do Bruno")

    get job_applications_url
    assert_response :success
    assert_select "h1", "Candidaturas"
    assert_select ".kanban .kanban__column", JobApplication::STATUSES.size
    assert_select ".ja-column--saved .kanban__card", 1
    assert_select ".ja-column--interview .kanban__card", 1
    assert_select ".kanban__card[data-allowed='applied withdrawn']", 1
    assert_match "Programador Rails", response.body
    assert_no_match "Segredo do Bruno", response.body
  end

  test "index shows the next open task on the card" do
    create_task(@user, title: "Enviar portefólio", job_application: @application, due_at: 2.days.from_now)
    create_task(@user, title: "Mais tarde", job_application: @application, due_at: 9.days.from_now)

    get job_applications_url
    assert_select ".ja-card__task", text: /Enviar portefólio/
  end

  test "index list view filters by status and search" do
    create_job_application(@user, title: "Designer", status: "interview")

    get job_applications_url(view: "list", status: "interview")
    assert_response :success
    assert_select "table.table tbody tr", 1
    assert_select "table.table tbody tr", text: /Designer/

    get job_applications_url(view: "list", q: "rails")
    assert_select "table.table tbody tr", 1
    assert_select "table.table tbody tr", text: /Programador Rails/
  end

  test "index list view with no matches shows an empty state" do
    get job_applications_url(view: "list", status: "offer")
    assert_response :success
    assert_select ".empty-state"
  end

  test "index without applications shows an empty state" do
    @application.destroy!
    get job_applications_url
    assert_response :success
    assert_select ".empty-state"
    assert_select ".kanban", 0
  end

  test "index ignores invalid view and status params" do
    get job_applications_url(view: "<script>", status: "hired")
    assert_response :success
    assert_select ".kanban"
  end

  # ---------- show ----------

  test "show renders the transitions, history and tasks" do
    task = create_task(@user, title: "Preparar CV", job_application: @application, task_type: "job")

    get job_application_url(@application)
    assert_response :success
    assert_select "h1", "Programador Rails"
    assert_select ".badge--saved"
    assert_select "form.ja-transition", 2
    assert_select "form.ja-transition input[name='transition[to]'][value='applied']"
    assert_select "form.ja-transition input[type=checkbox][name='transition[create_follow_up]']"
    assert_select ".timeline .timeline__item", 1
    assert_select ".timeline", text: /Vi no LinkedIn/
    assert_select "a[href=?]", task_path(task), text: "Preparar CV"
    assert_select "form[action=?]", create_task_job_application_path(@application)
    assert_select "form[action=?]", job_application_job_application_events_path(@application)
  end

  test "show offers an interview date when interview is the next step" do
    @application.update!(status: "applied")
    get job_application_url(@application)
    assert_select "input[type='datetime-local'][name='transition[interview_at]']"
  end

  test "show for a closed application has no transitions" do
    @application.update!(status: "rejected")
    get job_application_url(@application)
    assert_response :success
    assert_select "form.ja-transition", 0
    assert_select ".ja-closed"
  end

  test "show displays the job listing with an external link" do
    listing = @user.job_listings.create!(title: "Programador Rails", company_name: "Alfa", location: "Porto",
                                        url: "https://example.com/jobs/42")
    @application.update!(job_listing: listing)

    get job_application_url(@application)
    assert_select "a[href='https://example.com/jobs/42'][target=_blank][rel='noopener noreferrer']", text: /Abrir vaga/
    assert_match "Porto", response.body
  end

  test "show explains when there is no listing" do
    get job_application_url(@application)
    assert_select ".ja-listing__missing"
  end

  # ---------- new / create ----------

  test "new renders the manual form" do
    get new_job_application_url
    assert_response :success
    assert_select "form input[name='job_application[title]']"
    assert_select "input[name='job_application[job_listing_id]']", 0
  end

  test "new from a listing prefills the form" do
    listing = create_listing
    get new_job_application_url(job_listing_id: listing.id)
    assert_response :success
    assert_select "input[name='job_application[title]'][value='Backend Ruby']"
    assert_select "input[type=hidden][name='job_application[job_listing_id]'][value=?]", listing.id.to_s
  end

  test "new from a listing that already has an application redirects to it" do
    listing = create_listing
    @application.update!(job_listing: listing)
    get new_job_application_url(job_listing_id: listing.id)
    assert_redirected_to job_application_url(@application)
  end

  test "new with another user's listing is not found" do
    get new_job_application_url(job_listing_id: create_listing(users(:two)).id)
    assert_response :not_found
  end

  test "create a manual application" do
    assert_difference -> { @user.job_applications.count } => 1, -> { JobApplicationEvent.count } => 1 do
      post job_applications_url, params: { job_application: { title: "Analista", company_name: "Beta", notes: "Híbrido" } }
    end
    application = @user.job_applications.order(:id).last
    assert_redirected_to job_application_url(application)
    assert_equal "Candidatura criada.", flash[:notice]
    assert application.saved?
    assert AuditLog.exists?(action: "job_application.created", resource_id: application.id)
  end

  test "create ignores a status param" do
    post job_applications_url, params: { job_application: { title: "Analista", status: "offer" } }
    assert @user.job_applications.order(:id).last.saved?
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { title: "" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "create from a listing prefills and does not duplicate" do
    listing = create_listing

    assert_difference -> { @user.job_applications.count } => 1 do
      post job_applications_url, params: { job_application: { job_listing_id: listing.id } }
    end
    application = @user.job_applications.find_by!(job_listing: listing)
    assert_equal "Backend Ruby", application.title
    assert_equal "Gama", application.company_name

    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { job_listing_id: listing.id } }
    end
    assert_redirected_to job_application_url(application)
    assert_equal "Já tinhas uma candidatura para esta vaga.", flash[:notice]
  end

  test "create with another user's listing is not found" do
    foreign = create_listing(users(:two))
    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { job_listing_id: foreign.id, title: "X" } }
    end
    assert_response :not_found
  end

  # ---------- edit / update ----------

  test "edit renders the form" do
    get edit_job_application_url(@application)
    assert_response :success
    assert_select "input[name='job_application[title]'][value='Programador Rails']"
  end

  test "update changes details but never the status" do
    patch job_application_url(@application),
          params: { job_application: { title: "Programadora Rails", notes: "Nova nota", status: "offer" } }
    assert_redirected_to job_application_url(@application)
    @application.reload
    assert_equal "Programadora Rails", @application.title
    assert_equal "Nova nota", @application.notes
    assert @application.saved?
    assert AuditLog.exists?(action: "job_application.updated", resource_id: @application.id)
  end

  test "update with invalid data re-renders edit" do
    patch job_application_url(@application), params: { job_application: { title: "" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal "Programador Rails", @application.reload.title
  end

  # ---------- destroy ----------

  test "destroy removes the application and its history" do
    assert_difference -> { JobApplication.count } => -1, -> { JobApplicationEvent.count } => -1 do
      delete job_application_url(@application)
    end
    assert_redirected_to job_applications_url
    assert AuditLog.exists?(action: "job_application.deleted", resource_id: @application.id)
  end

  # ---------- transition ----------

  test "transition to applied with follow-up" do
    assert_difference -> { JobApplicationEvent.count } => 1, -> { @user.tasks.count } => 1 do
      patch transition_job_application_url(@application),
            params: { transition: { to: "applied", create_follow_up: "1", notes: "Via email" } }
    end
    assert_redirected_to job_application_url(@application)
    assert_match "Candidatura enviada", flash[:notice]
    assert_match "Follow-up: Programador Rails", flash[:notice]
    @application.reload
    assert @application.applied?
    assert_not_nil @application.applied_at
    assert_equal "Via email", @application.job_application_events.last.notes
  end

  test "transition to applied with a backdated send date" do
    patch transition_job_application_url(@application),
          params: { transition: { to: "applied", occurred_at: "2026-09-20T09:15", create_follow_up: "0" } }
    assert_equal Time.zone.local(2026, 9, 20, 9, 15), @application.reload.applied_at
  end

  test "transition to interview with a date creates the interview task" do
    @application.update!(status: "applied")
    interview_at = 4.days.from_now.change(sec: 0)
    patch transition_job_application_url(@application),
          params: { transition: { to: "interview", interview_at: interview_at.strftime("%Y-%m-%dT%H:%M") } }

    task = @user.tasks.find_by!(title: "Entrevista: Programador Rails")
    assert_equal interview_at, task.starts_at
    assert_equal 1, task.reminders.count
  end

  test "forbidden transition is refused with an alert" do
    assert_no_difference -> { JobApplicationEvent.count } do
      patch transition_job_application_url(@application), params: { transition: { to: "offer" } }
    end
    assert_redirected_to job_application_url(@application)
    assert_match "Não é possível passar", flash[:alert]
    assert @application.reload.saved?
  end

  test "transition from the kanban returns to the index" do
    patch transition_job_application_url(@application), params: { transition: { to: "applied" }, return_to: "index" }
    assert_redirected_to job_applications_url
  end

  test "transition ignores unknown return_to values" do
    patch transition_job_application_url(@application),
          params: { transition: { to: "applied" }, return_to: "https://evil.example.com" }
    assert_redirected_to job_application_url(@application)
  end

  # ---------- create_task ----------

  test "create_task creates a linked job task and opens its edit page" do
    assert_difference -> { @user.tasks.count } => 1 do
      post create_task_job_application_url(@application)
    end
    task = @user.tasks.order(:id).last
    assert_redirected_to edit_task_url(task)
    assert_equal "Candidatar-me: Programador Rails", task.title
    assert_equal @application, task.job_application
    assert task.type_job?
  end

  # ---------- authorization ----------

  test "another user cannot see or change the application" do
    sign_out
    sign_in_as(users(:two))

    get job_application_url(@application)
    assert_response :not_found
    get edit_job_application_url(@application)
    assert_response :not_found
    patch job_application_url(@application), params: { job_application: { title: "Hack" } }
    assert_response :not_found
    patch transition_job_application_url(@application), params: { transition: { to: "applied" } }
    assert_response :not_found
    assert_no_difference -> { Task.count } do
      post create_task_job_application_url(@application)
    end
    assert_response :not_found
    assert_no_difference -> { JobApplication.count } do
      delete job_application_url(@application)
    end
    assert_response :not_found

    @application.reload
    assert_equal "Programador Rails", @application.title
    assert @application.saved?
  end

  private
    def create_listing(user = @user)
      user.job_listings.create!(title: "Backend Ruby", company_name: "Gama", location: "Lisboa",
                                url: "https://example.com/jobs/#{SecureRandom.hex(4)}")
    end
end
