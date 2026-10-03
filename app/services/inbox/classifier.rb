module Inbox
  # Guesses what a company's email says from typical phrases (pt-PT, pt-BR and English).
  # Rejection wins over everything else, because rejections often also thank you for
  # applying or mention "next steps" for other candidates.
  #
  #   Inbox::Classifier.call(subject: "A tua candidatura", text: "Infelizmente…") # => "rejected"
  class Classifier
    RULES = {
      "rejected" => [
        "infelizmente", "lamentamos", "não vamos avançar", "nao vamos avancar", "não iremos avançar",
        "decidimos avançar com outros", "decidimos seguir com outros", "outros candidatos",
        "não foste selecionad", "não foi selecionad", "não prosseguir", "perfil não se enquadra",
        "unfortunately", "regret to inform", "not moving forward", "will not be moving forward",
        "decided to move forward with other", "decided to pursue other", "not been selected",
        "position has been filled", "we won't be proceeding", "not to proceed",
        "not to move forward", "decided not to", "won't be moving forward", "will not be progressing",
        "no longer under consideration", "not an exact fit", "move ahead with another candidate",
        "não avançaste", "não avançou", "candidatura encerrada", "processo encerrado", "não dar seguimento",
        "não foi possível avançar", "não seguir em frente", "optámos por outro", "optamos por outro"
      ],
      "offer" => [
        "proposta de trabalho", "proposta salarial", "temos o prazer de te oferecer", "carta de oferta",
        "gostaríamos de te fazer uma proposta", "job offer", "offer letter", "pleased to offer",
        "happy to offer", "extend an offer"
      ],
      "interview" => [
        "entrevista", "próxima fase", "proxima fase", "próxima etapa", "agendar uma conversa",
        "disponibilidade para", "teste técnico", "desafio técnico", "case study",
        "interview", "next step", "next round", "schedule a call", "technical assessment",
        "coding challenge", "your availability",
        "gostaríamos muito de te", "gostaríamos de te conhecer", "marcar uma reunião", "convidar-te para",
        "passaste para a próxima", "excelente resultado", "would like to invite you", "invite you to"
      ],
      "received" => [
        "recebemos a tua candidatura", "recebemos a sua candidatura", "obrigado pela tua candidatura",
        "obrigado pela sua candidatura", "candidatura foi recebida", "candidatura recebida",
        "thank you for applying", "thanks for applying", "we have received your application",
        "application received", "application has been received"
      ]
    }.freeze
    ORDER = %w[rejected offer interview received].freeze

    def self.call(subject:, text:)
      haystack = "#{subject}\n#{text}".downcase
      ORDER.find { |outcome| RULES[outcome].any? { |phrase| haystack.include?(phrase) } } || "unknown"
    end
  end
end
