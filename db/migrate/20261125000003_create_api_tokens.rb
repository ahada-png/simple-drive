# Bearer tokens. Only a SHA-256 digest is stored, never the token itself.
class CreateApiTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false, limit: 64
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
  end
end
