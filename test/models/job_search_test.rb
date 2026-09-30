require "test_helper"

class JobSearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid with name and source" do
    search = @user.job_searches.new(name: "  Rails em Lisboa  ", source: "linkedin", query: "  rails  ")
    assert search.valid?
    assert_equal "Rails em Lisboa", search.name
    assert_equal "rails", search.query
  end

  test "requires a name" do
    search = @user.job_searches.new(name: "", source: "linkedin")
    assert_not search.valid?
    assert search.errors.of_kind?(:name, :blank)
  end

  test "rejects unknown sources" do
    search = @user.job_searches.new(name: "X", source: "monster")
    assert_not search.valid?
    assert search.errors.key?(:source)
  end

  test "blank query becomes nil" do
    search = @user.job_searches.create!(name: "Só filtros", source: "indeed", query: "   ")
    assert_nil search.query
  end

  test "source labels in Portuguese" do
    assert_equal "LinkedIn", JobSearch.new(source: "linkedin").source_label
    assert_equal "Indeed", JobSearch.new(source: "indeed").source_label
    assert_equal "Outra", JobSearch.new(source: "other").source_label
  end

  test "allowed filter keys follow the source" do
    assert_includes JobSearch.new(source: "linkedin").allowed_filter_keys, "experience"
    assert_not_includes JobSearch.new(source: "linkedin").allowed_filter_keys, "radius"
    assert_includes JobSearch.new(source: "indeed").allowed_filter_keys, "radius"
  end

  test "filters from another source are reported as unsupported after switching source" do
    search = @user.job_searches.create!(name: "Indeed", source: "indeed")
    search.job_filters.create!(key: "radius", value: "25")
    search.job_filters.create!(key: "location", value: "Porto")
    search.update!(source: "linkedin")

    assert_equal [ "radius" ], search.reload.unsupported_filters.map(&:key)
    assert_not_includes search.search_url, "radius"
  end

  test "destroying a search keeps its listings" do
    search = @user.job_searches.create!(name: "Rails", source: "linkedin")
    listing = @user.job_listings.create!(title: "Dev", url: "https://example.com/job/1", job_search: search)

    search.destroy!
    assert_nil listing.reload.job_search_id
  end

  test "ordered puts active searches first" do
    paused = @user.job_searches.create!(name: "A pausada", source: "linkedin", active: false)
    active = @user.job_searches.create!(name: "B ativa", source: "linkedin")
    assert_equal [ active, paused ], @user.job_searches.ordered.to_a
  end
end
