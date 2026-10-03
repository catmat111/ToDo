require "test_helper"

class CompensationTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  def listing(**attrs)
    @user.job_listings.create!({ title: "Dev", url: "https://exemplo.pt/#{SecureRandom.hex(4)}" }.merge(attrs))
  end

  test "salary labels" do
    assert_equal "1 200–1 500 € / mês", listing(salary_min: 1200, salary_max: 1500).salary_label
    assert_equal "a partir de 30 000 € / ano", listing(salary_min: 30_000, salary_period: "year").salary_label
    assert_nil listing.salary_label
  end

  test "max must not be below min, work mode must be known" do
    record = @user.job_listings.new(title: "Dev", url: "https://exemplo.pt/x", salary_min: 2000, salary_max: 1000, work_mode: "lua")
    assert_not record.valid?
    assert record.errors[:salary_max].any?
    assert record.errors[:work_mode].any?
  end

  test "filters by work mode and minimum monthly salary (yearly over 14 payments)" do
    remote = listing(work_mode: "remote", salary_max: 1500)
    yearly = listing(work_mode: "hybrid", salary_min: 28_000, salary_period: "year") # = 2000/month
    low = listing(work_mode: "remote", salary_max: 900)

    assert_equal [ remote, low ].map(&:id).sort, @user.job_listings.with_work_mode("remote").ids.sort
    assert_equal [ remote, yearly ].map(&:id).sort, @user.job_listings.paying_at_least(1200).ids.sort
  end

  test "an application created from a listing copies salary and work mode" do
    source = listing(work_mode: "hybrid", salary_min: 1300, salary_max: 1600)
    application = JobApplications::Create.call(user: @user, params: { job_listing_id: source.id }).job_application
    assert_equal "hybrid", application.work_mode
    assert_equal 1600, application.salary_max
  end
end
