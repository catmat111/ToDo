class JobFilter < ApplicationRecord
  OPERATORS = %w[equals contains excludes].freeze
  OPERATOR_LABELS = { "equals" => "Igual", "contains" => "Contém", "excludes" => "Exclui" }.freeze

  # Keys each source understands. JobSearches::Sources adapters translate them to URLs.
  ALLOWED_KEYS = {
    "linkedin" => %w[location recency job_type experience remote keywords],
    "indeed" => %w[location recency job_type radius remote keywords],
    "other" => %w[location recency job_type remote keywords]
  }.freeze
  KEY_LABELS = {
    "location" => "Localização", "recency" => "Recência", "job_type" => "Tipo de contrato",
    "experience" => "Experiência", "remote" => "Remoto", "radius" => "Raio (km)", "keywords" => "Palavras-chave"
  }.freeze

  # Free text keys accept every operator; the others are structured and only accept "equals".
  FREE_TEXT_KEYS = %w[keywords location].freeze

  # Canonical values for structured keys (what the adapters understand) and their pt-PT labels.
  VALUE_OPTIONS = {
    "recency" => {
      "24h" => "Últimas 24 horas", "3d" => "Últimos 3 dias", "week" => "Última semana",
      "2weeks" => "Últimas 2 semanas", "month" => "Último mês"
    },
    "job_type" => {
      "full_time" => "Tempo inteiro", "part_time" => "Part-time", "contract" => "Contrato",
      "temporary" => "Temporário", "internship" => "Estágio"
    },
    "experience" => {
      "internship" => "Estágio", "entry" => "Júnior", "associate" => "Associado",
      "mid_senior" => "Intermédio / Sénior", "director" => "Diretor", "executive" => "Executivo"
    },
    "remote" => { "yes" => "Remoto", "hybrid" => "Híbrido", "no" => "Presencial" }
  }.freeze

  # Friendly spellings accepted in the form, mapped to the canonical value.
  VALUE_ALIASES = {
    "recency" => {
      "1d" => "24h", "24" => "24h", "24_horas" => "24h", "day" => "24h", "dia" => "24h", "hoje" => "24h",
      "3_dias" => "3d", "3days" => "3d",
      "7d" => "week", "semana" => "week", "7_dias" => "week",
      "14d" => "2weeks", "2_semanas" => "2weeks", "2_weeks" => "2weeks",
      "30d" => "month", "mes" => "month", "mês" => "month", "30_dias" => "month"
    },
    "job_type" => {
      "fulltime" => "full_time", "tempo_inteiro" => "full_time", "full" => "full_time",
      "parttime" => "part_time", "part" => "part_time", "meio_tempo" => "part_time", "tempo_parcial" => "part_time",
      "contrato" => "contract", "temporario" => "temporary", "temporário" => "temporary", "temp" => "temporary",
      "estagio" => "internship", "estágio" => "internship"
    },
    "experience" => {
      "estagio" => "internship", "estágio" => "internship", "junior" => "entry", "júnior" => "entry",
      "entry_level" => "entry", "associado" => "associate", "mid" => "mid_senior", "senior" => "mid_senior",
      "sénior" => "mid_senior", "intermedio" => "mid_senior", "intermédio" => "mid_senior",
      "diretor" => "director", "executivo" => "executive"
    },
    "remote" => {
      "true" => "yes", "1" => "yes", "sim" => "yes", "remote" => "yes", "remoto" => "yes",
      "false" => "no", "0" => "no", "nao" => "no", "não" => "no", "presencial" => "no", "on_site" => "no",
      "hibrido" => "hybrid", "híbrido" => "hybrid"
    }
  }.freeze

  RADIUS_SUGGESTIONS = %w[5 10 25 50 100].freeze
  MAX_RADIUS = 200

  belongs_to :job_search

  normalizes :value, with: ->(value) { value.to_s.squish }

  before_validation :canonicalize_value

  validates :key, presence: true
  validates :value, presence: true, length: { maximum: 200 }
  validates :operator, inclusion: { in: OPERATORS }
  validate :key_allowed_for_source
  validate :operator_allowed_for_key
  validate :value_allowed_for_key

  def self.canonical_value(key, raw)
    options = VALUE_OPTIONS[key.to_s]
    return raw if options.nil? || raw.blank?

    token = raw.to_s.strip.downcase.gsub(/[\s-]+/, "_")
    return token if options.key?(token)
    VALUE_ALIASES.fetch(key.to_s, {}).fetch(token, raw)
  end

  # Values suggested in the form (datalist) for each key.
  def self.suggestions_for(key)
    return VALUE_OPTIONS[key].to_a if VALUE_OPTIONS.key?(key)
    return RADIUS_SUGGESTIONS.map { |km| [ km, "#{km} km" ] } if key == "radius"
    []
  end

  def self.free_text?(key)
    FREE_TEXT_KEYS.include?(key.to_s)
  end

  def label
    KEY_LABELS.fetch(key, key.to_s.humanize)
  end

  def operator_label
    OPERATOR_LABELS.fetch(operator, operator.to_s.humanize)
  end

  def value_label
    return "#{value} km" if key == "radius"
    VALUE_OPTIONS.dig(key, value) || value
  end

  def excludes?
    operator == "excludes"
  end

  def supported_by_source?
    job_search.present? && ALLOWED_KEYS.fetch(job_search.source, []).include?(key)
  end

  private
    def canonicalize_value
      self.value = self.class.canonical_value(key, value) if value.present?
    end

    def key_allowed_for_source
      return if job_search.nil? || key.blank?
      allowed = ALLOWED_KEYS.fetch(job_search.source, [])
      return if allowed.include?(key)
      errors.add(:key, "não é suportado pela fonte #{job_search.source_label}")
    end

    def operator_allowed_for_key
      return if key.blank? || self.class.free_text?(key) || operator == "equals"
      errors.add(:operator, "tem de ser «Igual» para o filtro #{label}")
    end

    def value_allowed_for_key
      return if value.blank?

      if (options = VALUE_OPTIONS[key])
        return if options.key?(value)
        errors.add(:value, "não é válido para #{label} (opções: #{options.values.join(', ')})")
      elsif key == "radius"
        return if value.match?(/\A\d{1,3}\z/) && value.to_i.between?(1, MAX_RADIUS)
        errors.add(:value, "tem de ser um número de quilómetros entre 1 e #{MAX_RADIUS}")
      end
    end
end
