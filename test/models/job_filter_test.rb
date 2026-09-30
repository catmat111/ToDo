require "test_helper"

class JobFilterTest < ActiveSupport::TestCase
  setup do
    @linkedin = users(:one).job_searches.create!(name: "LinkedIn", source: "linkedin")
    @indeed = users(:one).job_searches.create!(name: "Indeed", source: "indeed")
    @other = users(:one).job_searches.create!(name: "Google", source: "other")
  end

  test "keys are validated per source" do
    assert @linkedin.job_filters.new(key: "experience", value: "entry").valid?
    assert_not @indeed.job_filters.new(key: "experience", value: "entry").valid?
    assert_not @other.job_filters.new(key: "experience", value: "entry").valid?

    assert @indeed.job_filters.new(key: "radius", value: "25").valid?
    radius = @linkedin.job_filters.new(key: "radius", value: "25")
    assert_not radius.valid?
    assert_includes radius.errors[:key].join, "LinkedIn"
  end

  test "every allowed key is accepted by its source" do
    samples = { "location" => "Lisboa", "recency" => "week", "job_type" => "full_time", "experience" => "entry",
                "remote" => "yes", "radius" => "10", "keywords" => "rails" }
    JobFilter::ALLOWED_KEYS.each do |source, keys|
      search = { "linkedin" => @linkedin, "indeed" => @indeed, "other" => @other }.fetch(source)
      keys.each do |key|
        filter = search.job_filters.new(key: key, value: samples.fetch(key))
        assert filter.valid?, "#{source}/#{key}: #{filter.errors.full_messages.to_sentence}"
      end
    end
  end

  test "unknown keys are rejected" do
    assert_not @linkedin.job_filters.new(key: "salary", value: "50000").valid?
  end

  test "requires a value and a known operator" do
    assert_not @linkedin.job_filters.new(key: "keywords", value: " ").valid?
    assert_not @linkedin.job_filters.new(key: "keywords", value: "rails", operator: "near").valid?
  end

  test "structured values are canonicalised from friendly spellings" do
    assert_equal "week", @linkedin.job_filters.create!(key: "recency", value: "Semana").value
    assert_equal "24h", @linkedin.job_filters.create!(key: "recency", value: "1d").value
    assert_equal "full_time", @linkedin.job_filters.create!(key: "job_type", value: "Full-time").value
    assert_equal "part_time", @linkedin.job_filters.create!(key: "job_type", value: "part time").value
    assert_equal "mid_senior", @linkedin.job_filters.create!(key: "experience", value: "Sénior").value
    assert_equal "yes", @linkedin.job_filters.create!(key: "remote", value: "sim").value
  end

  test "structured values outside the options are rejected" do
    filter = @linkedin.job_filters.new(key: "recency", value: "ontem à noite")
    assert_not filter.valid?
    assert filter.errors.key?(:value)

    assert_not @indeed.job_filters.new(key: "radius", value: "muito").valid?
    assert_not @indeed.job_filters.new(key: "radius", value: "900").valid?
  end

  test "structured keys only accept the equals operator" do
    filter = @linkedin.job_filters.new(key: "job_type", value: "internship", operator: "excludes")
    assert_not filter.valid?
    assert filter.errors.key?(:operator)

    assert @linkedin.job_filters.new(key: "keywords", value: "estágio", operator: "excludes").valid?
    assert @linkedin.job_filters.new(key: "location", value: "Lisboa", operator: "contains").valid?
  end

  test "labels" do
    filter = @linkedin.job_filters.new(key: "recency", value: "week", operator: "equals")
    assert_equal "Recência", filter.label
    assert_equal "Igual", filter.operator_label
    assert_equal "Última semana", filter.value_label
    assert_equal "25 km", @indeed.job_filters.new(key: "radius", value: "25").value_label
    assert_equal "Exclui", JobFilter.new(operator: "excludes").operator_label
  end

  test "suggestions per key" do
    assert_includes JobFilter.suggestions_for("recency").map(&:first), "24h"
    assert_includes JobFilter.suggestions_for("job_type").map(&:first), "part_time"
    assert_includes JobFilter.suggestions_for("radius").map(&:first), "25"
    assert_empty JobFilter.suggestions_for("keywords")
  end
end
