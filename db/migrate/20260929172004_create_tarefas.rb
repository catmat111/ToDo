class CreateTarefas < ActiveRecord::Migration[8.1]
  def change
    create_table :tarefas do |t|
      t.string :nome
      t.boolean :concluido
      t.date :data_inicio
      t.date :data_fim
      t.date :data_criado
      t.string :tipo


      t.timestamps
    end
  end
end
