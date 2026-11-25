# Storage table for the "database" backend. Deliberately separate from the
# `blobs` metadata table so the database backend is just another adapter.
class CreateBlobContents < ActiveRecord::Migration[7.2]
  def change
    create_table :blob_contents do |t|
      t.string :key,  null: false
      t.binary :data, null: false
      t.datetime :created_at, null: false
    end

    add_index :blob_contents, :key, unique: true
  end
end
